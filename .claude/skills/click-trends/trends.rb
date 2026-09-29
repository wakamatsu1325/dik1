# encoding: utf-8
# frozen_string_literal: true
#
# Dog URL の投稿で、クリック数が伸びやすい作品・投稿文・画像の傾向を出す。
# clicks.json / history.json / runs/*.json / notes.json と集計表（xlsx）を読むだけで、何も書かない。
#
#   ruby trends.rb                 # 全投稿
#   ruby trends.rb --sheet PATH    # 集計表の場所を変える（既定 ~/Desktop/Dog URL 集計.xlsx）
#
# 物差しは「投稿から24時間後のクリック数（投稿後）」。経過時間のそろえ方は click-growth/analyze.rb と同じ。
Encoding.default_external = Encoding::UTF_8
require "json"
require "time"
require "rexml/document"

# /usr/bin/ruby は 2.6 なので filter_map が無い
unless [].respond_to?(:filter_map)
  module Enumerable
    def filter_map(&blk)
      map(&blk).select { |x| x }
    end
  end
end

DIR = ENV["DOG_URL_DIR"] || File.expand_path("~/Library/Application Support/Dog URL")
si = ARGV.index("--sheet")
SHEET = si ? ARGV[si + 1] : (ENV["DOG_URL_SHEET"] || File.expand_path("~/Desktop/Dog URL 集計.xlsx"))
DAY = 1440

clicks  = JSON.parse(File.read(File.join(DIR, "clicks.json")))
history = JSON.parse(File.read(File.join(DIR, "history.json")))
history = history["entries"] if history.is_a?(Hash)
notes   = (JSON.parse(File.read(File.join(DIR, "notes.json"))) rescue {})

runs = {}
Dir[File.join(DIR, "runs", "*.json")].sort.each do |f|
  r = (JSON.parse(File.read(f)) rescue nil) or next
  u = r["short_url"] or next
  runs[u] = r # 同じURLで複数回なら新しい実行
end

def median(a)
  s = a.sort
  return nil if s.empty?
  v = s.size.odd? ? s[s.size / 2] : (s[s.size / 2 - 1] + s[s.size / 2]) / 2.0
  v == v.round ? v.round : v.round(1)
end

# 同順位は平均順位にしたスピアマンの順位相関
def spearman(x, y)
  rank = lambda do |a|
    s = a.each_with_index.sort_by(&:first)
    r = Array.new(a.size)
    i = 0
    while i < s.size
      j = i
      j += 1 while j + 1 < s.size && s[j + 1][0] == s[i][0]
      (i..j).each { |k| r[s[k][1]] = (i + j) / 2.0 }
      i = j + 1
    end
    r
  end
  rx, ry = rank.call(x), rank.call(y)
  n = x.size.to_f
  mx, my = rx.sum / n, ry.sum / n
  num = rx.zip(ry).sum { |a, b| (a - mx) * (b - my) }
  den = Math.sqrt(rx.sum { |a| (a - mx)**2 } * ry.sum { |b| (b - my)**2 })
  den.zero? ? nil : (num / den).round(2)
end

# ---- 集計表を読む（gem を足さない。unzip で XML を抜いて REXML で読む） ----
def read_xlsx(path)
  q = ->(n) { "'" + path.gsub("'", "'\\\\''") + "'" + " " + n }
  ss = []
  sx = `/usr/bin/unzip -p #{q.call('xl/sharedStrings.xml')} 2>/dev/null`
  unless sx.empty?
    REXML::Document.new(sx).elements.each("sst/si") { |e| ss << REXML::XPath.match(e, ".//t").map(&:text).join }
  end
  doc = REXML::Document.new(`/usr/bin/unzip -p #{q.call('xl/worksheets/sheet1.xml')}`)
  col = ->(ref) { ref[/\A[A-Z]+/].each_char.inject(0) { |n, c| n * 26 + c.ord - 64 } - 1 }
  rows = []
  doc.elements.each("worksheet/sheetData/row") do |row|
    h = {}
    row.elements.each("c") do |c|
      v = case c.attributes["t"]
          when "s" then ss[c.elements["v"].text.to_i]
          when "inlineStr" then REXML::XPath.match(c, ".//t").map(&:text).join
          else c.elements["v"]&.text
          end
      h[col.call(c.attributes["r"])] = v
    end
    rows << h
  end
  head = rows.shift
  rows.map { |h| head.map { |i, name| [name, h[i]] }.to_h }
end

abort "集計表が無い: #{SHEET}（ruby bin/shorten.rb sheet で作る）" unless File.exist?(SHEET)
sheet = read_xlsx(SHEET).map { |r| [r["短縮URL"], r] }.to_h
sheet_at = File.mtime(SHEET)

# ---- 投稿ごとの経過時間つき記録（click-growth/analyze.rb と同じ組み方） ----
posts = history.filter_map do |e|
  u = e["short"]
  rows = clicks[u]
  next if rows.nil? || rows.empty?
  mark = rows.find { |x| x["mark"] == "post" }
  t0 = mark ? Time.parse(mark["at"]) : Time.parse(e["created_at"])
  base = mark ? mark["hits"] : 0
  pts = rows.map { |x| [(Time.parse(x["at"]) - t0) / 60.0, x["hits"] - base] }.sort_by(&:first)
  # 物差し。2026-09-29 から X.gd。それまでの TinyURL は同じ回線のクリックを1件に丸めるので少なめに出る
  { url: u, alias: u[/[^\/]+\z/], t0: t0, pts: pts, run: runs[u], xgd: u.start_with?("https://x.gd/"),
    early: pts.any? { |m, _| m.between?(0, 60) } }
end

# 経過 m 分の値。前後の記録の間が狭ければ線形補間、広ければ ±25% 以内の実測の最寄り。取れなければ nil
def value_at(p, m)
  pts = p[:pts]
  pr = pts.select { |a, _| a <= m }.last
  nx = pts.find { |a, _| a >= m }
  if pr && nx && (nx[0] - pr[0]) <= [40, m * 0.5].max
    return (nx[0] == pr[0] ? nx[1] : pr[1] + (nx[1] - pr[1]) * (m - pr[0]) / (nx[0] - pr[0])).round
  end
  near = pts.select { |a, _| (a - m).abs <= m * 0.25 }.min_by { |a, _| (a - m).abs }
  near && near[1]
end

# 24時間の値。記録がまばらで value_at が取れないときだけ、前後の記録を直線で結ぶ（印を付ける）
def day_value(p)
  v = value_at(p, DAY)
  return [v, false] if v
  pr = p[:pts].select { |a, _| a <= DAY }.last
  nx = p[:pts].find { |a, _| a >= DAY }
  return nil unless pr && nx
  [(pr[1] + (nx[1] - pr[1]) * (DAY - pr[0]) / (nx[0] - pr[0])).round, true]
end

cands = posts.select { |p| p[:run] && p[:early] }
deleted, cands = cands.partition { |p| notes[p[:url]].to_s.include?("削除") }
missing = cands.reject { |p| sheet[p[:url]] }
cands -= missing
done, running = cands.partition { |p| p[:pts].last[0] >= DAY }

S = sheet
data = done.filter_map do |p|
  v, rough = day_value(p) || next
  s = S[p[:url]]
  t = p[:run]["text_a"].to_s.lines.first.to_s.strip
  g = s["ジャンル"].to_s
  owner = s["1枚目の画像"].to_s
  { p: p, v: v, rough: rough, text: t, s: s,
    v80: value_at(p, 80), v180: value_at(p, 180),
    sold: (Integer(s["売れた数"]) rescue nil),
    imp: (Integer(s["YTインプ"]) rescue nil),
    work: s["商品名"].to_s, owner: owner, genre: g,
    price: s["最安実売(生成時)"].to_f, mins: s["尺(分)"].to_f,
    hour: p[:t0].hour }
end
abort "24時間経った投稿が無い" if data.empty?

vals = data.map { |d| d[:v] }.sort
MED = median(vals)
q1 = vals[(vals.size * 0.25).floor]
q3 = vals[(vals.size * 0.75).floor]
grade = ->(v) { v >= q3 ? "上位1/4" : v >= MED ? "中央値以上" : v > q1 ? "中央値未満" : "下位1/4" }

# ---- 比べる属性。はい/いいえ の2つに割れるものだけ。nil を返した投稿（分からない）はその属性の比較から外す ----
FACTORS = [
  ["区分が素人",            ->(d) { d[:s]["区分"] == "素人" }],
  ["単体作品",              ->(d) { d[:genre].include?("単体作品") }],
  ["ベスト・総集編",        ->(d) { d[:genre].include?("ベスト") }],
  ["1枚目が3分割",          ->(d) { v = d[:s]["1枚目3分割"].to_s; v.empty? ? nil : v == "3分割" }],
  ["1枚目が作品フォルダ",   ->(d) { d[:owner].start_with?("作品") }],
  ["文に「セール」",        ->(d) { d[:text].include?("セール") }],
  ["文が問いかけ（？）",    ->(d) { d[:text].match?(/[？?]/) }],
  ["文に👍😍",               ->(d) { d[:text].include?("👍😍") }],
  ["文に数字",              ->(d) { d[:text].match?(/[0-9０-９]/) }],
  ["文に「..」",            ->(d) { d[:text].include?("..") }],
  ["文に美女/美少女",       ->(d) { d[:text].match?(/美女|美少女/) }],
  ["投稿17〜23時",          ->(d) { (17..23).cover?(d[:hour]) }],
  ["投稿5〜16時",           ->(d) { (5..16).cover?(d[:hour]) }],
  ["実売200円以下",         ->(d) { d[:price].positive? && d[:price] <= 200 }],
  ["尺240分以上",           ->(d) { d[:mins] >= 240 }],
  ["セール中（生成時）",    ->(d) { d[:s]["セール(生成時)"] == "あり" }],
  ["画像2枚以上",           ->(d) { (d[:p][:run]["images"] || []).size >= 2 }]
].freeze

fmtv = ->(d) { d[:rough] ? "#{d[:v]}*" : d[:v].to_s }

puts "## 対象"
puts "24時間経った投稿 #{data.size}件（実行記録あり・序盤の記録あり）  中央値 #{MED} / 下位1/4の境 #{q1} / 上位1/4の境 #{q3}"
puts "物差し: 投稿から24時間後のクリック数（投稿後）。* は記録がまばらで前後の記録を直線で結んだ値"
n_xgd = data.count { |d| d[:p][:xgd] }
if n_xgd.positive?
  puts "⚠ 数え方が2種類混ざっている: TinyURL #{data.size - n_xgd}件 / X.gd #{n_xgd}件（順位表で x の付いた行）。" \
       "TinyURL（2026-09-29 まで）は同じ回線のクリックを丸めて少なめなので、X.gd の投稿は上に出やすい"
end
puts

puts "## 24時間の順位（多い順）"
puts "24時間 | 80分 | 3時間 | 売れた数 | YTインプ | 区分 | 1枚目 | 投稿時刻 | 投稿文 | 作品"
data.sort_by { |d| -d[:v] }.each do |d|
  s = d[:s]
  first = [d[:owner].sub(/\A作品: /, "作品:")[0, 16], s["1枚目3分割"] == "3分割" ? "3分割" : nil].compact.join(" ")
  puts [fmtv.call(d) + (d[:p][:xgd] ? " x" : ""), d[:v80] || "-", d[:v180] || "-", d[:sold] || "-", d[:imp] || "-", s["区分"], first,
        d[:p][:t0].strftime("%m-%d %H時"), d[:text], "#{d[:work][0, 30]}（#{d[:p][:alias]}）"].join(" | ")
end
puts

puts "## 属性ごとの比較（はい / いいえ。件数・24時間の中央値・中央値以上の件数）"
factor_sets = {}
FACTORS.each do |name, f|
  known = data.reject { |d| f.call(d).nil? }
  unk = data.size - known.size
  yes, no = known.partition { |d| f.call(d) }
  next if yes.size < 2 || no.size < 2
  m = ->(a) { median(a.map { |d| d[:v] }) }
  up = ->(a) { "#{a.count { |d| d[:v] >= MED }}/#{a.size}" }
  diff = m.call(yes) - m.call(no)
  mark = diff.abs >= MED * 0.3 ? (diff.positive? ? "  ▲" : "  ▼") : ""
  # 重なりを見るのは差が出た属性だけ。多かった側（▲ならはい、▼ならいいえ）の投稿で比べる
  unless mark.empty?
    side = diff.positive? ? yes : no
    factor_sets["#{name}#{diff.positive? ? '' : '＝いいえ'}"] = side.map { |d| d[:p][:url] }
  end
  puts "#{name}: はい n=#{yes.size} 中央値#{m.call(yes)} 中央値以上#{up.call(yes)} | いいえ n=#{no.size} 中央値#{m.call(no)} 中央値以上#{up.call(no)}#{unk.positive? ? "（不明#{unk}件は外した）" : ''}#{mark}"
end
puts "（▲▼は中央値の差が全体の中央値の3割以上。件数が少ないので候補止まり）"
puts

puts "## ▲▼どうしの重なり（多かった側の投稿で、件数が少ない方の3/4以上がもう片方にも入る組。どちらが効いたか分けられない）"
overl = []
factor_sets.keys.combination(2) do |a, b|
  x, y = factor_sets[a], factor_sets[b]
  small = [x.size, y.size].min
  overl << "#{a}（#{x.size}件） × #{b}（#{y.size}件）  共通#{(x & y).size}件" if (x & y).size >= small * 0.75
end
puts overl.empty? ? "なし" : overl
puts

puts "## 1枚目の画像の登場人物ごと（2回以上使ったものだけ）"
by_owner = data.group_by { |d| d[:owner].sub(/\A[⭐️]+/, "") }.select { |k, a| !k.empty? && a.size >= 2 }
if by_owner.empty?
  puts "なし"
else
  by_owner.sort_by { |_, a| -median(a.map { |d| d[:v] }) }.each do |k, a|
    puts "#{k}: #{a.map { |d| d[:v] }.join(' ')}（中央値#{median(a.map { |d| d[:v] })}）"
  end
end
puts

# 投稿文の言い回し: 2投稿以上に出た文字列（2文字以上）を、出た投稿の組が同じなら一番長いものだけ残す。
# 助詞で始まる・終わる断片（「の美」「女が」）や、ひらがなだけの断片は言い回しとして読めないので外す
puts "## 2回以上使った言い回し（投稿文の1行目から。出た投稿の24時間値）"
grams = Hash.new { |h, k| h[k] = [] }
data.each_with_index do |d, i|
  t = d[:text].gsub(/【?🉐セール】|[.。…]+\z/, "")
  (2..[t.size, 30].min).each do |n|
    (0..t.size - n).each do |k|
      g = t[k, n]
      next if g =~ /\A[\s.。、！!？?【】👇のがにとをはでも]|[\s.。、【】のがにとをはで]\z/ || g =~ /\A\p{Hiragana}+\z/
      grams[g] << i unless grams[g].include?(i)
    end
  end
end
multi = grams.select { |_, ids| ids.size >= 2 }
keep = multi.reject { |g, ids| multi.any? { |h, ids2| h != g && h.include?(g) && ids2 == ids } }
lines = keep.map do |g, ids|
  vs = ids.map { |i| data[i][:v] }
  side = vs.all? { |v| v >= MED } ? "全部中央値以上" : vs.all? { |v| v < MED } ? "全部中央値未満" : "混在"
  [side, -ids.size, g, vs]
end.sort_by { |side, n, g, _| [side == "混在" ? 1 : 0, n, -g.size] }
lines.first(25).each { |side, _, g, vs| puts "「#{g}」 #{vs.sort.reverse.join(' ')}  → #{side}" }
puts

puts "## 序盤と24時間のつながり（順位相関）"
[[80, "80分"], [180, "3時間"]].each do |m, l|
  pr = data.select { |d| d[m == 80 ? :v80 : :v180] }
  next if pr.size < 4
  puts "#{l}と24時間: #{spearman(pr.map { |d| d[m == 80 ? :v80 : :v180] }, pr.map { |d| d[:v] })}（#{pr.size}件）"
end
sp = data.select { |d| d[:sold] }
puts "24時間と売れた数: #{spearman(sp.map { |d| d[:v] }, sp.map { |d| d[:sold] })}（#{sp.size}件）" if sp.size >= 4
ip = data.select { |d| d[:imp] }
puts "24時間とYTインプ: #{spearman(ip.map { |d| d[:v] }, ip.map { |d| d[:imp] })}（#{ip.size}件）" if ip.size >= 4
puts

puts "## 時期（前半と後半）"
half = data.sort_by { |d| d[:p][:t0] }
a, b = half.each_slice((half.size / 2.0).ceil).to_a
puts "前半 #{a.first[:p][:t0].strftime('%m-%d')}〜 n=#{a.size} 中央値#{median(a.map { |d| d[:v] })} / " \
     "後半 #{b.first[:p][:t0].strftime('%m-%d')}〜 n=#{b.size} 中央値#{median(b.map { |d| d[:v] })}"
puts

unless running.empty?
  puts "## 集計中（24時間未満。同じ経過時間の全投稿と比べる）"
  running.sort_by { |p| p[:t0] }.each do |p|
    now = p[:pts].last[0].floor
    cur = p[:pts].last[1]
    peers = data.filter_map { |d| value_at(d[:p], now) }
    below = peers.count { |v| v < cur }
    s = S[p[:url]]
    label = now >= 120 ? "#{(now / 60.0).round(1)}時間" : "#{now}分"
    puts "#{p[:alias]} #{p[:t0].strftime('%m-%d %H時')} 経過#{label} #{cur}  / 同時点の中央値#{median(peers) || '-'}  " \
         "下から#{below + 1}番目（#{peers.size + 1}件中） | #{s['区分']} #{s['1枚目3分割']} | #{p[:run]['text_a'].to_s.lines.first.to_s.strip}"
  end
  puts
end

puts "除外: 削除した投稿 #{deleted.map { |p| "#{p[:alias]}（#{notes[p[:url]]}）" }.join(' ')}"
puts "除外: 子リンク・序盤の記録が無い初期の投稿"
unless missing.empty?
  puts "⚠ 集計表に行が無い投稿 #{missing.map { |p| p[:alias] }.join(' ')} → ruby bin/shorten.rb sheet で書き直してから流し直す"
end
newest_run = runs.values.map { |r| Time.parse(r["posted_at"] || r["created_at"]) rescue nil }.compact.max
if newest_run && newest_run > sheet_at
  puts "⚠ 集計表（#{sheet_at.strftime('%m-%d %H:%M')}）より新しい投稿がある。売れた数・1枚目の列が古い可能性"
end
blank = data.select { |d| d[:s]["1枚目3分割"].to_s.empty? }
puts "⚠ 「1枚目3分割」が空の行 #{blank.map { |d| d[:p][:alias] }.join(' ')}（3分割の比較から漏れる）" unless blank.empty?
