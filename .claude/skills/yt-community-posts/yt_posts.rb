# YouTube チャンネルのコミュニティ投稿（本文・画像）を全件取って1フォルダへまとめる。
#
#   ruby yt_posts.rb <チャンネルURL or @handle>...  [--out DIR]
#   ruby yt_posts.rb --bookmarks <書き出したブックマーク.html> --folder <フォルダ名> [--list] [--out DIR]
#     [--skip 文字列]...
#     （フォルダ以下＝サブフォルダ含む の YouTube チャンネルを重複を除いて全部回す。--list は一覧だけ出す。
#       --skip はブックマーク名か URL にその文字列を含むチャンネルを外す）
#   ruby yt_posts.rb <投稿URL（youtube.com/post/ID）>... [--out DIR]
#     （個別の投稿：画像だけを DIR(既定 ~/Desktop) の直下へ。txt は作らない。チャンネルURLと混ぜて渡してもよい）
#
# 保存先: <DIR(既定 ~/Desktop/コミュニティ投稿)>/<チャンネル名>_投稿/  投稿0件のチャンネルはフォルダを作らない。
#   直下に 画像「高評価数_本文1行目_N.拡張子」と 投稿一覧.txt（全投稿の情報・新しい順）。
# 取り直すと、高評価数が変わった画像は付け直し（リネーム。落とし直さない）、新しい投稿だけ落とす。
# 今回の一覧に出なかった過去の投稿（削除・取得上限）は、画像も記録も消さずに一覧の末尾へ残す。
# ログイン・APIキー不要。標準Ruby 2.6 と curl だけで動く。
require 'json'
require 'net/http'
require 'uri'
require 'fileutils'
Encoding.default_external = 'UTF-8'
$stdout.sync = true # ファイルへ流しても1チャンネルごとに結果が見えるように

UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 Chrome/128 Safari/537.36'
SEP = "\n==============================\n\n"
MAX_HEAD_BYTES = 180 # ファイル名の上限は255バイト。本文1行目がこれを超えたら切る

def posts_url(arg)
  s = arg.strip
  s = "https://www.youtube.com/#{s}" if s.start_with?('@')
  s = "https://#{s}" unless s =~ %r{\Ahttps?://}
  s = s.sub(%r{[?#].*\z}, '').sub(%r{/+\z}, '')
  s = s.sub(%r{/(featured|videos|shorts|streams|posts|community|about|playlists)\z}, '')
  "#{s}/posts"
end

def fetch_posts(arg)
  html = raw = nil
  3.times do |k| # 連続で回すとたまに中身の無いページが返る。404（チャンネル削除）なら何度読んでも無い
    sleep 2 * k
    html = `curl -sL -H 'Accept-Language: ja' -A '#{UA}' '#{posts_url(arg)}'`.force_encoding('UTF-8')
    raw = html[/var ytInitialData = (\{.*?\});<\/script>/m, 1]
    break if raw || html.include?('<title>404 Not Found')
  end
  raw or abort "ページを読めない（チャンネル削除か一時的な失敗）: #{arg}"
  data = JSON.parse(raw)
  ver = html[/"INNERTUBE_CLIENT_VERSION":"([^"]+)"/, 1]
  title = data.dig('metadata', 'channelMetadataRenderer', 'title') or abort "チャンネル名が取れない: #{arg}"
  posts = []
  token = nil
  collect = lambda do |o|
    case o
    when Hash
      if o['backstagePostThreadRenderer']
        pr = o.dig('backstagePostThreadRenderer', 'post', 'backstagePostRenderer')
        posts << pr if pr
      else
        o.each_value { |v| collect.(v) }
      end
    when Array
      # 投稿の並びと同じ配列にある continuation だけが「次の投稿」。別の continuation（チャンネル概要）を拾うと1ページで止まる
      if o.any? { |v| v.is_a?(Hash) && v['backstagePostThreadRenderer'] }
        c = o.find { |v| v.is_a?(Hash) && v['continuationItemRenderer'] }
        token = c && c.dig('continuationItemRenderer', 'continuationEndpoint', 'continuationCommand', 'token')
      end
      o.each { |v| collect.(v) }
    end
  end
  collect.(data)
  while token
    t = token
    token = nil
    uri = URI('https://www.youtube.com/youtubei/v1/browse?prettyPrint=false')
    req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json', 'User-Agent' => UA)
    req.body = JSON.dump(context: { client: { clientName: 'WEB', clientVersion: ver, hl: 'ja', gl: 'JP' } }, continuation: t)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
    abort "続きの取得に失敗 HTTP #{res.code}（#{posts.size}件まで）" unless res.code == '200'
    collect.(JSON.parse(res.body.force_encoding('UTF-8')))
    sleep 0.3
  end
  [title, posts.uniq { |x| x['postId'] }]
end

def head_of(text, post_id)
  h = text.lines.first.to_s.strip.tr('/:', '／：')
  h = post_id if h.empty?
  h = h[0...-1] while h.bytesize > MAX_HEAD_BYTES
  h
end

def ext_of(path)
  k = `file -b "#{path}"`
  k.start_with?('PNG') ? 'png' : k.start_with?('GIF') ? 'gif' : k.start_with?('RIFF') && k.include?('WebP') ? 'webp' : 'jpg'
end

# 前回の 投稿一覧.txt から 投稿ID => {block:, files: [...]}
def read_previous(list_path)
  return {} unless File.exist?(list_path)
  body = File.read(list_path)
  body = body.split("\n\n", 2)[1].to_s if body.start_with?('全')
  body.split(SEP).each_with_object({}) do |blk, h|
    id = blk[/^投稿ID: (\S+)/, 1] or next
    h[id] = { block: blk.chomp + "\n", files: blk.scan(/^  (\S.*?)  \(/).flatten }
  end
end

def save_channel(arg, root)
  title, all = fetch_posts(arg)
  # アンケート投稿は取らない（だいきんぐの指定）。前に保存した分があれば画像ごと消す
  polls, posts = all.partition { |x| x.dig('backstageAttachment', 'pollRenderer') }
  out = File.join(root, "#{title.tr('/:', '／：')}_投稿")
  list_path = File.join(out, '投稿一覧.txt')
  prev = read_previous(list_path)
  dropped = 0
  polls.each do |x|
    old = prev.delete(x['postId']) or next
    old[:files].each { |f| FileUtils.rm_f(File.join(out, f)) }
    dropped += 1
  end
  if posts.empty? && prev.empty?
    FileUtils.rm_f(list_path)
    if Dir.exist?(out) && (Dir.children(out) - ['.DS_Store']).empty?
      FileUtils.rm_f(File.join(out, '.DS_Store'))
      Dir.rmdir(out)
    end
    puts "#{title}: 投稿0件（アンケート#{polls.size}件は除外）フォルダは作らない"
    return
  end
  FileUtils.mkdir_p(out)
  fetched_at = Time.now.strftime('%F %H:%M')
  used = {}
  jobs = []
  renamed = 0
  entries = posts.map do |x|
    id = x['postId']
    text = (x.dig('contentText', 'runs') || []).map { |r| r['navigationEndpoint'] ? '' : r['text'] }.join.gsub(%r{https?://\S+}, '')
    likes = x.dig('voteCount', 'simpleText') || '0'
    base = "#{likes}_#{head_of(text, id)}"
    base += "_#{id}" if used[base] # 高評価数も1行目も同じ投稿が重なったときだけ区別する
    used[base] = true
    att = x['backstageAttachment'] || {}
    list = att.dig('postMultiImageRenderer', 'images')&.map { |i| i['backstageImageRenderer'] } || [att['backstageImageRenderer']].compact
    srcs = list.map { |r| r.dig('image', 'thumbnails').last['url'].sub(/=s\d+.*\z/, '=s0') }
    extra = []
    vid = att.dig('videoRenderer', 'videoId')
    extra << "動画: https://www.youtube.com/watch?v=#{vid}" if vid
    old = prev.dig(id, :files) || []
    names = srcs.each_with_index.map do |u, i|
      o = old[i]
      if o && File.exist?(File.join(out, o))
        n = "#{base}_#{i + 1}#{File.extname(o)}"
        if n != o
          File.rename(File.join(out, o), File.join(out, n))
          renamed += 1
        end
        n
      else
        job = { url: u, stem: "#{base}_#{i + 1}", name: nil }
        jobs << job
        job
      end
    end
    { x: x, id: id, text: text, likes: likes, base: base, names: names, srcs: srcs, extra: extra }
  end

  # 新しい画像だけ並列で落とす
  fails = []
  q = Queue.new
  jobs.each { |j| q << j }
  Array.new(8) {
    Thread.new do
      while (j = (q.pop(true) rescue nil))
        tmp = File.join(out, ".#{j[:stem]}.part")
        if system('curl', '-sfL', '--retry', '3', j[:url], '-o', tmp)
          j[:name] = "#{j[:stem]}.#{ext_of(tmp)}"
          File.rename(tmp, File.join(out, j[:name]))
        else
          FileUtils.rm_f(tmp)
          j[:name] = "#{j[:stem]}.jpg（取得失敗）"
          fails << j[:url]
        end
      end
    end
  }.each(&:join)

  blocks = entries.map do |e|
    names = e[:names].map { |n| n.is_a?(Hash) ? n[:name] : n }
    <<~B
      ■ #{e[:base]}
      #{e[:text].rstrip}
      ----
      高評価数: #{e[:likes]}
      投稿日時: #{e[:x].dig('publishedTimeText', 'runs', 0, 'text')}（#{fetched_at} 時点）
      投稿URL: https://www.youtube.com/post/#{e[:id]}
      投稿ID: #{e[:id]}
      #{e[:extra].map { |l| l + "\n" }.join}画像:
      #{names.each_with_index.map { |f, i| "  #{f}  (#{e[:srcs][i]})" }.join("\n")}
    B
  end
  seen = entries.map { |e| e[:id] }
  kept = prev.reject { |id, _| seen.include?(id) }.values.map { |v| v[:block] }
  header = "全#{blocks.size + kept.size}件（#{fetched_at} 取得・新しい順#{kept.empty? ? '' : "。末尾#{kept.size}件は今回の一覧に出なかった過去の記録"}）\n\n"
  File.write(list_path, header + (blocks + kept).join(SEP))

  imgs = entries.sum { |e| e[:names].size }
  oldest = all.last.dig('publishedTimeText', 'runs', 0, 'text')
  puts "#{title}: 投稿#{posts.size}件（最古 #{oldest}） 画像#{imgs}枚（新規#{jobs.size - fails.size}・付け直し#{renamed}・失敗#{fails.size}）#{kept.empty? ? '' : " 過去の記録#{kept.size}件を保持"}#{polls.empty? ? '' : " アンケート#{polls.size}件は除外#{dropped > 0 ? "（保存済み#{dropped}件を削除）" : ''}"}"
  puts "  → #{out}"
  puts '  ⚠︎ ちょうど200件：ログインなしの上限で古い投稿が切れている可能性あり' if all.size == 200
  fails.each { |u| puts "  失敗: #{u}" }
end

# ブックマークHTML（Chrome/Brave の書き出し）から、指定フォルダ以下（サブフォルダ含む）の YouTube チャンネルを取り出す
def bookmark_channels(file, folder)
  h = File.read(file)
  i = h.index(/<H3[^>]*>\[?#{Regexp.escape(folder)}\]?<\/H3>/i) or abort "フォルダが無い: #{folder}"
  depth = 0
  out = []
  h[i..-1].scan(/<DL>|<\/DL>|<A [^>]*HREF="([^"]+)"[^>]*>([^<]*)<\/A>/i) do |u, t|
    m = $~[0]
    if m =~ /\A<DL>/i
      depth += 1
    elsif m =~ /\A<\/DL>/i
      depth -= 1
      break if depth.zero?
    elsif depth > 0 && u =~ %r{youtube\.com/(@[^/?#]+|channel/[^/?#]+|c/[^/?#]+|user/[^/?#]+)}
      out << ["https://www.youtube.com/#{$1}", t.sub(/ - YouTube\z/, '')]
    end
  end
  out.uniq { |c, _| URI.decode_www_form_component(c).downcase }
end

# 投稿URL（youtube.com/post/ID、…/community?lb=ID）なら投稿ID、チャンネルなら nil
def post_id_of(arg)
  arg[%r{youtube\.com/post/([\w-]+)}, 1] || arg[%r{[?&]lb=([\w-]+)}, 1]
end

# 個別の投稿1件：画像だけを dir の直下へ（txt は作らない）
def save_single(arg, dir)
  id = post_id_of(arg)
  html = raw = nil
  3.times do |k|
    sleep 2 * k
    html = `curl -sL -H 'Accept-Language: ja' -A '#{UA}' 'https://www.youtube.com/post/#{id}'`.force_encoding('UTF-8')
    raw = html[/var ytInitialData = (\{.*?\});<\/script>/m, 1]
    break if raw
  end
  raw or abort "ページを読めない: #{arg}"
  x = nil
  find = lambda { |o| return if x; case o when Hash then (o['backstagePostRenderer'] ? x = o['backstagePostRenderer'] : o.each_value { |v| find.(v) }) when Array then o.each { |v| find.(v) } end }
  find.(JSON.parse(raw))
  abort "投稿が見つからない（削除・非公開）: #{arg}" unless x && x['postId'] == id
  text = (x.dig('contentText', 'runs') || []).map { |r| r['navigationEndpoint'] ? '' : r['text'] }.join
  base = "#{x.dig('voteCount', 'simpleText') || '0'}_#{head_of(text, id)}"
  att = x['backstageAttachment'] || {}
  list = att.dig('postMultiImageRenderer', 'images')&.map { |i| i['backstageImageRenderer'] } || [att['backstageImageRenderer']].compact
  abort "画像の無い投稿: #{arg}" if list.empty?
  FileUtils.mkdir_p(dir)
  list.each_with_index do |r, i|
    u = r.dig('image', 'thumbnails').last['url'].sub(/=s\d+.*\z/, '=s0')
    tmp = File.join(dir, ".#{base}_#{i + 1}.part")
    system('curl', '-sfL', '--retry', '3', u, '-o', tmp) or abort "画像の取得に失敗: #{u}"
    name = "#{base}_#{i + 1}.#{ext_of(tmp)}"
    File.rename(tmp, File.join(dir, name))
    puts name
  end
  puts "  → #{dir}"
end

root = nil
args = ARGV.map { |a| a.dup.force_encoding('UTF-8') } # LANG 無しで呼ばれると ASCII-8BIT で来る
if (i = args.index('--out'))
  root = File.expand_path(args[i + 1])
  args.slice!(i, 2)
end
if (i = args.index('--bookmarks'))
  file = args[i + 1]
  args.slice!(i, 2)
  j = args.index('--folder') or abort '--bookmarks には --folder が要る'
  folder = args[j + 1]
  args.slice!(j, 2)
  chans = bookmark_channels(file, folder)
  # --skip <文字列>（何度でも）：ブックマーク名か URL に含むチャンネルを外す（取り直し不要のチャンネル）
  skips = []
  while (k = args.index('--skip'))
    skips << args[k + 1]
    args.slice!(k, 2)
  end
  chans.reject! { |c, t| skips.any? { |s| t.include?(s) || URI.decode_www_form_component(c).include?(s) } }
  if args.delete('--list')
    chans.each { |c, t| puts "#{t} | #{c}" }
    puts "#{chans.size} チャンネル"
    exit
  end
  args += chans.map(&:first)
end
abort 'usage: ruby yt_posts.rb <チャンネルURL or @handle>... [--out DIR] / --bookmarks FILE --folder NAME [--list]' if args.empty?
args.each do |a|
  begin
    if post_id_of(a)
      save_single(a, root || File.expand_path('~/Desktop')) # 個別の投稿は既定でデスクトップ直下
    else
      save_channel(a, root || File.expand_path('~/Desktop/コミュニティ投稿'))
    end
  rescue SystemExit, StandardError => e
    puts "#{a}: 失敗 #{e.message}"
  end
end
