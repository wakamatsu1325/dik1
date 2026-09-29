# encoding: utf-8
# frozen_string_literal: true
#
# Dog URL の投稿ごとのクリック数の伸びを、全投稿と経過時間をそろえて比べる。
# clicks.json / history.json / runs/*.json を読むだけで、何も書かない。
#
#   ruby analyze.rb              # 最新の投稿を対象にする
#   ruby analyze.rb 5y4jz9pa     # 短縮URLかaliasで対象を指定
#   ruby analyze.rb --interval   # 投稿間隔の検証（新しい投稿の前後で、前の投稿の伸びがどう変わったか）
#
Encoding.default_external = Encoding::UTF_8
require "json"
require "time"

# /usr/bin/ruby は 2.6 なので filter_map が無い
unless [].respond_to?(:filter_map)
  module Enumerable
    def filter_map(&blk)
      map(&blk).select { |x| x }
    end
  end
end

DIR = ENV["DOG_URL_DIR"] || File.expand_path("~/Library/Application Support/Dog URL")
# 物差し（どこで数えたか）。2026-09-29 から X.gd で発行している。それまでの TinyURL は同じ回線のクリックを
# 1件に丸めるので少なめに出る。同じ物差しの投稿が SAME_METER_MIN 件以上あれば、比較相手をそれだけに絞る。
SAME_METER_MIN = 5
METER_LABEL = { xgd: "X.gd", tinyurl: "TinyURL" }.freeze
def meter_of(url)
  url.to_s.start_with?("https://x.gd/") ? :xgd : :tinyurl
end
CHECKPOINTS = [20, 40, 80, 180, 360, 720, 1440, 2880].freeze # 分
LABEL = { 20 => "20分", 40 => "40分", 80 => "80分", 180 => "3時間", 360 => "6時間", 720 => "12時間", 1440 => "24時間", 2880 => "48時間" }.freeze

clicks  = JSON.parse(File.read(File.join(DIR, "clicks.json")))
history = JSON.parse(File.read(File.join(DIR, "history.json")))
history = history["entries"] if history.is_a?(Hash)

runs = {}
Dir[File.join(DIR, "runs", "*.json")].sort.each do |f|
  r = (JSON.parse(File.read(f)) rescue nil) or next
  u = r["short_url"] or next
  runs[u] = r # 同じURLで複数回なら新しい実行
end

def median(a)
  s = a.sort
  return nil if s.empty?
  s.size.odd? ? s[s.size / 2] : (s[s.size / 2 - 1] + s[s.size / 2]) / 2.0
end

posts = history.filter_map do |e|
  u = e["short"]
  rows = clicks[u]
  next if rows.nil? || rows.empty?
  mark = rows.find { |x| x["mark"] == "post" }
  run = runs[u]
  t0 = mark ? Time.parse(mark["at"]) : Time.parse(e["created_at"])
  base = mark ? mark["hits"] : 0
  pts = rows.map { |x| [(Time.parse(x["at"]) - t0) / 60.0, x["hits"] - base] }.sort_by(&:first)
  title = run && (run["text_a"] || "").lines.first.to_s.strip
  {
    url: u, alias: u[/[^\/]+\z/], t0: t0, marked: !mark.nil?, pts: pts, rows: rows, meter: meter_of(u),
    title: title.to_s.empty? ? "" : title[0, 24],
    sub: run.nil?, # 投稿の実行記録に紐づかないリンク（Cの返信内など）
    early: pts.any? { |m, _| m.between?(0, 60) } # 序盤の記録があるか
  }
end

# 経過 m 分の値。前後の記録の間隔が狭ければ線形補間、広ければ ±25% 以内の実測の最寄りを使う。
# 返り値 [値, 実測の分 or nil(補間)]、取れなければ nil
def value_at(p, m)
  pts = p[:pts]
  pr = pts.select { |a, _| a <= m }.last
  nx = pts.find { |a, _| a >= m }
  if pr && nx && (nx[0] - pr[0]) <= [40, m * 0.5].max
    v = nx[0] == pr[0] ? nx[1] : pr[1] + (nx[1] - pr[1]) * (m - pr[0]) / (nx[0] - pr[0])
    return [v.round, nil]
  end
  near = pts.select { |a, _| (a - m).abs <= m * 0.25 }.min_by { |a, _| (a - m).abs }
  near && [near[1], near[0].round]
end

# ---- 投稿間隔の検証 -------------------------------------------------------
#
# 新しい投稿 N の時刻 T の前後で、直近48時間以内に投げた前の投稿 P の1分あたりの伸びを比べる。
#   前: T の約80分前（20〜240分前で一番近い記録）から T まで
#   後: T から約80分後（20〜240分後で一番近い記録）まで
# T の値は、投稿時に積んだ `mark: neighbor` の行（2026-09-26 から）を使い、無ければ T の前後15分以内の実測。
# 補間はしない（前後の記録を直線で結ぶと、前と後の伸びが同じ直線から出て比が1に寄るため）。
# 投稿は放っておいても伸びが落ちるので、「自然減の目安」を横に置く:
#   他の投稿が同じ経過時間の前後80分をどう動いたか（その間に別の投稿が出ていない回だけ）の後/前の中央値。
if ARGV.include?("--interval")
  tpl = posts.reject { |p| p[:sub] || !p[:early] }.sort_by { |p| p[:t0] }
  post_times = tpl.map { |p| p[:t0] }
  d24i = tpl.filter_map { |p| value_at(p, 1440)&.first }.sort
  q1 = d24i[(d24i.size * 0.25).floor]
  q3 = d24i[(d24i.size * 0.75).floor]
  med24 = median(d24i)
  grade = lambda do |v|
    next "-" unless v
    v >= q3 ? "上位1/4" : v >= med24 ? "中央値以上" : v > q1 ? "中央値未満" : "下位1/4"
  end
  # 経過 m 分の値。補間の許容を広げたもの（前後の記録の間が3時間まで）
  loose = lambda do |p, m|
    pr = p[:pts].select { |a, _| a <= m }.last
    nx = p[:pts].find { |a, _| a >= m }
    next nil unless pr && nx && nx[0] - pr[0] <= 180
    nx[0] == pr[0] ? nx[1] : pr[1] + (nx[1] - pr[1]) * (m - pr[0]) / (nx[0] - pr[0])
  end
  # 自然減の目安: 経過 a 分の前後80分で、その間に別の投稿が出ていない投稿の 後/前 の比。
  # band を渡すと「同格」だけに絞る: 経過 a 分の累計が前の投稿の 1/2〜2倍 の投稿（2026-09-28 から）。
  # 全体の目安だけだと、弱い投稿が普段から平均より早く落ちるだけで「落ちた」と出てしまい、
  # 新しい投稿のせいか、もともと弱いからかを切り分けられなかった（10組中「落ちた」6組が全部、24時間で中央値未満の投稿だった）。
  # 強さは T の時点で分かる値（経過 a 分の累計）で測る。24時間の成績で絞ると、干渉の結果そのもので絞ることになるため。
  natural = lambda do |a, except, band = nil|
    tpl.filter_map do |p|
      next if p.equal?(except) || a < 80
      from = p[:t0] + (a - 80) * 60
      to = p[:t0] + (a + 80) * 60
      next if post_times.any? { |t| t > from && t < to && t != p[:t0] }
      v0 = loose.call(p, a - 80)
      v1 = loose.call(p, a)
      v2 = loose.call(p, a + 80)
      next unless v0 && v1 && v2 && v1 - v0 > 0
      next if band && !(v1 >= band / 2.0 && v1 <= band * 2.0)
      (v2 - v1) / (v1 - v0)
    end
  end
  rows_out = []
  tpl.each do |n|
    t = n[:t0]
    tpl.each do |pv|
      next unless pv[:t0] < t && t - pv[:t0] <= 48 * 3600
      age = (t - pv[:t0]) / 60.0
      base = pv[:rows].find { |r| r["mark"] == "post" }&.dig("hits") || 0
      nb = pv[:rows].find { |r| r["mark"] == "neighbor" && r["by"] == n[:url] && r["phase"] == "post" }
      near = pv[:pts].select { |a, _| (a - age).abs <= 15 }.min_by { |a, _| (a - age).abs }
      vt = nb ? nb["hits"] - base : near&.last
      next unless vt
      before = pv[:pts].select { |a, _| a.between?(age - 240, age - 20) }.min_by { |a, _| (a - (age - 80)).abs }
      after = pv[:pts].select { |a, _| a.between?(age + 20, age + 240) }.min_by { |a, _| (a - (age + 80)).abs }
      next unless before && after
      rb = (vt - before[1]) / (age - before[0])
      ra = (after[1] - vt) / (after[0] - age)
      nat_all = natural.call(age.round, pv)
      nat = natural.call(age.round, pv, vt)
      rows_out << {
        n: n, p: pv, gap: age, rb: rb, ra: ra, ratio: rb > 0 ? ra / rb : nil, vt: vt,
        nat: nat.empty? ? nil : median(nat), nat_n: nat.size, src: nb ? "記録" : "実測",
        nat_all: nat_all.empty? ? nil : median(nat_all), nat_all_n: nat_all.size,
        win: [(age - before[0]).round, (after[0] - age).round], g: grade.call(value_at(pv, 1440)&.first)
      }
    end
  end
  # 判定するのは、前の投稿がまだ伸びていて（1分0.1件以上）、同格の自然減の目安が2件以上ある組だけ。
  # 0.01件/分どうしの比や、1件だけの目安は揺れが大きすぎて意味が無い。
  # 全体の目安での判定も参考に並べる（同格の目安が作れない組が多いうちは、見比べるため）。
  judgeable = ->(r) { r[:ratio] && r[:nat] && r[:rb] >= 0.1 && r[:nat_n] >= 2 }
  judgeable_all = ->(r) { r[:ratio] && r[:nat_all] && r[:rb] >= 0.1 && r[:nat_all_n] >= 2 }
  verdict = lambda do |ratio, base|
    ratio < base * 0.7 ? "▼落ちた" : ratio > base * 1.3 ? "△保った" : "＝なみ"
  end
  puts "## 投稿間隔の検証（#{rows_out.size}組）"
  puts "新しい投稿 ← 前の投稿 | 間隔 | T時点の累計 | 前の投稿の1分あたり 前→後 | 後/前 | 同格の目安(件数) | 全体の目安(件数) | 前の投稿の24時間 | 判定（同格） [参考: 全体]"
  rows_out.each do |r|
    ratio = r[:ratio] ? r[:ratio].round(2) : "-"
    nat = r[:nat] ? "#{r[:nat].round(2)}(#{r[:nat_n]})" : "-"
    nat_all = r[:nat_all] ? "#{r[:nat_all].round(2)}(#{r[:nat_all_n]})" : "-"
    flag = judgeable.call(r) ? verdict.call(r[:ratio], r[:nat]) : "（判定外）"
    ref = judgeable_all.call(r) ? " [全体: #{verdict.call(r[:ratio], r[:nat_all])}]" : ""
    puts "#{r[:n][:t0].strftime('%m-%d %H:%M')} #{r[:n][:alias]} ← #{r[:p][:alias]} | #{(r[:gap] / 60).round(1)}時間 | #{r[:vt]} | " \
         "#{r[:rb].round(2)}→#{r[:ra].round(2)}（前#{r[:win][0]}分/後#{r[:win][1]}分、T値=#{r[:src]}） | #{ratio} | #{nat} | #{nat_all} | #{r[:g]} | #{flag}#{ref}"
  end
  count = lambda do |rows, base_key|
    d = rows.count { |r| r[:ratio] < r[base_key] * 0.7 }
    u = rows.count { |r| r[:ratio] > r[base_key] * 1.3 }
    "落ちた #{d} / なみ #{rows.size - d - u} / 保った #{u}"
  end
  judged = rows_out.select { |r| judgeable.call(r) }
  judged_all = rows_out.select { |r| judgeable_all.call(r) }
  puts
  puts "判定できた #{judged.size}組（同格の目安。前の投稿が1分0.1件以上伸びていて、同格の目安が2件以上）: #{count.call(judged, :nat)}"
  puts "  うち前の投稿が投稿から3.5時間以内: #{count.call(judged.select { |r| r[:gap] <= 210 }, :nat)} / それ以降: #{count.call(judged.reject { |r| r[:gap] <= 210 }, :nat)}"
  puts "参考: 全体の目安で判定できた #{judged_all.size}組: #{count.call(judged_all, :nat_all)}（弱い投稿ほど『落ちた』に寄る。結論には使わない）"
  puts "前の投稿の記録（mark: neighbor）が付いた組: #{rows_out.count { |r| r[:src] == '記録' }}（2026-09-26 以降の投稿から増える）"
  exit 0
end

arg = ARGV[0]
target =
  if arg
    posts.find { |p| p[:url] == arg || p[:alias] == arg[/[^\/]+\z/] } or abort "見つからない: #{arg}"
  else
    posts.reject { |p| p[:sub] }.max_by { |p| p[:t0] }
  end
# 序盤の記録が無い投稿（09-10以前）は、実際に投げたかも怪しいものが混ざるので比較に入れない
all_peers = posts.reject { |p| p[:sub] || !p[:early] || p.equal?(target) }
same_meter = all_peers.select { |p| p[:meter] == target[:meter] }
# 同じ物差しの投稿が揃うまでは全投稿と比べ、物差しが混ざっていると断る
peers = same_meter.size >= SAME_METER_MIN ? same_meter : all_peers
meter_note =
  if peers.equal?(same_meter)
    "比較相手は同じ物差し（#{METER_LABEL[target[:meter]]}）の#{peers.size}件だけ"
  else
    mixed = all_peers.group_by { |p| p[:meter] }.map { |m, a| "#{METER_LABEL[m]} #{a.size}件" }.join(" / ")
    "⚠ 物差しが混ざっている（対象は#{METER_LABEL[target[:meter]]}、比較相手 #{mixed}）。" \
      "同じ物差しが#{SAME_METER_MIN}件に満たないので全部と比べた。TinyURLは同じ回線を丸めて少なめなので、X.gdの対象は上に出やすい"
  end
elapsed = target[:pts].last[0]

fmt = ->(r) { r ? (r[1] ? "#{r[0]}(#{r[1]}分)" : r[0].to_s) : "-" }

puts "## 対象"
puts "#{target[:alias]}  #{target[:t0].strftime('%m-%d(%a) %H:%M')} #{target[:marked] ? '投稿時刻あり' : '起点=生成時刻'}  #{target[:title]}"
puts "経過 #{(elapsed / 60).round(1)}時間  投稿後 #{target[:pts].last[1]}  物差し #{METER_LABEL[target[:meter]]}"
puts meter_note
puts
puts "## 対象の区間ごとの増分"
target[:pts].each_cons(2) do |(a, va), (b, vb)|
  next if b <= 0
  d = vb - va
  rate = b > a ? (d / (b - a)).round(2) : 0
  puts "  #{a.round}分→#{b.round}分  +#{d}  (#{rate}/分)"
end
puts

reached = CHECKPOINTS.select { |m| m <= elapsed * 1.05 }
puts "## 経過時間ごとの順位（投稿の実行記録があるものだけ。子リンクは除外）"
reached.each do |m|
  tv = value_at(target, m) or next
  vals = peers.filter_map { |p| (p[:early] || m >= 1440) && value_at(p, m)&.first }
  next if vals.empty?
  below = vals.count { |v| v < tv[0] }
  puts "#{LABEL[m]}: 対象 #{fmt[tv]}  / 比較#{vals.size}件 中央値#{median(vals)} 最低#{vals.min} 最高#{vals.max}  → 下から#{below + 1}番目（#{vals.size + 1}件中）"
end
# 今の経過時間での順位。節目の間にいると、節目の表だけでは今の位置が出ないため。
if elapsed >= 10 && elapsed < 2880 && !CHECKPOINTS.any? { |m| (m - elapsed).abs < 3 }
  now_m = elapsed.floor
  tv_now = target[:pts].last[1]
  vals = peers.filter_map { |p| (p[:early] || now_m >= 1440) && value_at(p, now_m)&.first }
  unless vals.empty?
    below = vals.count { |v| v < tv_now }
    label = now_m >= 120 ? "#{(now_m / 60.0).round(1)}時間" : "#{now_m}分"
    puts "今（#{label}）: 対象 #{tv_now}  / 比較#{vals.size}件 中央値#{median(vals)} 最低#{vals.min} 最高#{vals.max}  → 下から#{below + 1}番目（#{vals.size + 1}件中）"
  end
end
puts

d24 = peers.filter_map { |p| (v = value_at(p, 1440)) && [p, v[0]] }.sort_by(&:last)
puts "## 24時間の分布（#{d24.size}件）  中央値 #{median(d24.map(&:last))}"
puts d24.map { |p, v| "#{v}(#{p[:alias]})" }.join("  ")
puts

# 見込みは節目ではなく「今の経過時間」から出す。節目まで戻ると、その後の伸び（失速）を捨ててしまうため。
base_m = elapsed.floor
base_label = base_m >= 120 ? "#{(base_m / 60.0).round(1)}時間" : "#{base_m}分"
if base_m >= 10 && elapsed < 1440
  tv = target[:pts].last[1]
  ratios = peers.filter_map do |p|
    next unless p[:early] || base_m >= 360
    a = value_at(p, base_m) or next
    b = value_at(p, 1440) or next
    next if a[0] <= 0
    [p, a[0], b[0], (b[0].to_f / a[0]).round(2)]
  end.sort_by(&:last)
  unless ratios.empty?
    rs = ratios.map(&:last)
    puts "## 24時間の見込み（今の#{base_label} → 24時間の倍率、#{ratios.size}件）"
    ratios.each { |p, a, b, r| puts "  #{p[:alias]} #{a}→#{b}  ×#{r}  #{p[:title]}" }
    lo, md, hi = (tv * rs.min).round, (tv * median(rs)).round, (tv * rs.max).round
    rank = d24.count { |_, v| v < md }
    puts "倍率 最低×#{rs.min} 中央×#{median(rs).round(2)} 最高×#{rs.max}"
    puts "対象 #{tv} → 見込み #{lo}〜#{hi}、中央 #{md}（24時間分布で下から#{rank + 1}番目相当 / #{d24.size + 1}件中）"
    puts
  end
end

# 24時間で中央値以上だった投稿が、次の節目でいくつあったか = 分かれ目の目安
nxt = CHECKPOINTS.find { |m| m > elapsed && m < 1440 }
if nxt && !d24.empty?
  med = median(d24.map(&:last))
  up = d24.select { |_, v| v >= med }.filter_map { |p, _| value_at(p, nxt)&.first }
  dn = d24.select { |_, v| v < med }.filter_map { |p, _| value_at(p, nxt)&.first }
  puts "## 次の節目（#{LABEL[nxt]}）の分かれ目"
  puts "24時間で中央値以上だった投稿の#{LABEL[nxt]}値: #{up.sort.join(' ')}（最低 #{up.min || '-'}）"
  puts "中央値未満だった投稿の#{LABEL[nxt]}値: #{dn.sort.join(' ')}（最高 #{dn.max || '-'}）"
  puts
end

puts "## 24時間で上位1/4だった投稿の序盤（逆転の前例を見る）"
q3 = d24.map(&:last)[(d24.size * 0.75).floor] if d24.any?
d24.select { |_, v| q3 && v >= q3 }.each do |p, v|
  puts "  #{p[:alias]} 20分 #{fmt[value_at(p, 20)]} / 80分 #{fmt[value_at(p, 80)]} / 3時間 #{fmt[value_at(p, 180)]} → 24時間 #{v}  #{p[:title]}"
end
puts
excluded = posts.select { |p| p[:sub] }.map { |p| p[:alias] }
no_early = posts.reject { |p| p[:sub] || p[:early] }.map { |p| p[:alias] }
puts "除外: 子リンク #{excluded.join(' ')} / 序盤の記録なし #{no_early.join(' ')}"
puts "起点: 投稿時刻の記録があるものはその時点、無いものは生成時刻（TinyURLは検証の1回程度が混ざる）"
puts meter_note
