# frozen_string_literal: true
# 反応集ショートなどに使われている映像の引用元を X で探す。
#   prep   : 参考動画を落とし、調べる区間のコマ一覧と切り出し位置を決めるための1コマを出す
#   search : ログイン済みのデバッグ Chrome（CDP 9333）で X を検索し、動画付き投稿を候補に積む（既定の上限 100 本）
#   fetch  : 候補の本文と動画を api.fxtwitter.com から取る（ログイン不要）
#   match  : 区間のコマと候補動画のコマを、縮小グレーの正規化相互相関で比べて順位を出す
# 標準 Ruby 2.6 と curl だけ。yt-dlp / deno / ffmpeg は Dog React・YT DL が置いている実体を使う。
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8
require 'json'; require 'socket'; require 'net/http'; require 'securerandom'
require 'base64'; require 'uri'; require 'fileutils'; require 'open3'; require 'time'

HOME = ENV['HOME'].to_s.dup.force_encoding('UTF-8')
FF = ["#{HOME}/Desktop/Dog Tools/【work】/YT DL/bin/ffmpeg", '/opt/homebrew/bin/ffmpeg', '/usr/local/bin/ffmpeg'].find { |p| File.executable?(p) }
YT_BIN = ["#{HOME}/Library/Application Support/Dog React/bin", "#{HOME}/Desktop/Dog Tools/【work】/YT DL/bin"].find { |d| File.executable?("#{d}/yt-dlp") }
PORT = 9333
MATCH = 0.80 # これ以上なら同じ映像とみなす（自己検証：15%拡大した同じ映像で 0.86、別物は 0.5〜0.67）

abort 'ffmpeg が見つからない' unless FF

args = ARGV.map { |a| a.dup.force_encoding('UTF-8') }
cmd = args.shift
opts = { limit: 100, top: 5, scroll: 8 }
rest = []
until args.empty?
  a = args.shift
  case a
  when '--work' then opts[:work] = File.expand_path(args.shift)
  when '--from' then opts[:from] = args.shift.to_f
  when '--to' then opts[:to] = args.shift.to_f
  when '--crop' then opts[:crop] = args.shift
  when '--since' then opts[:since] = args.shift
  when '--until' then opts[:until] = args.shift
  when '--limit' then opts[:limit] = args.shift.to_i
  when '--top' then opts[:top] = args.shift.to_i
  when '--scroll' then opts[:scroll] = args.shift.to_i
  when '--latest' then opts[:latest] = true
  else rest << a
  end
end
abort '--work DIR を付ける' unless opts[:work]
W = opts[:work]
FileUtils.mkdir_p(W)
META = File.join(W, 'meta.json')
CANDS = File.join(W, 'candidates.json')
meta = File.exist?(META) ? JSON.parse(File.read(META)) : {}
save_meta = -> { File.write(META, JSON.pretty_generate(meta)) }

def ff(*a)
  out, st = Open3.capture2e(FF, '-loglevel', 'error', '-y', *a)
  warn out.force_encoding('UTF-8').lines.reject { |l| l.include?('Fontconfig') }.join unless st.success?
  st.success?
end

def duration(path)
  o, = Open3.capture2e(FF, '-i', path)
  m = o.force_encoding('UTF-8')[/Duration: (\d+):(\d+):([\d.]+)/] ? [$1, $2, $3] : nil
  m ? m[0].to_i * 3600 + m[1].to_i * 60 + m[2].to_f : 0.0
end

JST = ->(s) { (Time.parse(s) + 9 * 3600).strftime('%Y-%m-%d %H:%M') rescue s.to_s }

# ---- CDP（デバッグ Chrome の自分用タブ） ---------------------------------------------
class Tab
  def initialize
    t = JSON.parse(Net::HTTP.start('127.0.0.1', PORT) { |h| h.send_request('PUT', '/json/new?about:blank') }.body)
    @id = t['id']; u = URI(t['webSocketDebuggerUrl'])
    @s = TCPSocket.new(u.host, u.port)
    @s.write("GET #{u.path} HTTP/1.1\r\nHost: #{u.host}:#{u.port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" \
             "Sec-WebSocket-Key: #{Base64.strict_encode64(SecureRandom.random_bytes(16))}\r\nSec-WebSocket-Version: 13\r\n\r\n")
    while (l = @s.gets) && l != "\r\n"; end
    @n = 0
    call('Emulation.setFocusEmulationEnabled', enabled: true)
  end

  def frame(str)
    b = str.b; m = SecureRandom.random_bytes(4)
    h = [0x81].pack('C') + (b.size < 126 ? [0x80 | b.size].pack('C') : b.size < 65_536 ? [0xFE, b.size].pack('Cn') : [0xFF, b.size].pack('CQ>'))
    @s.write(h + m + b.bytes.each_with_index.map { |c, i| c ^ m.getbyte(i % 4) }.pack('C*'))
  end

  def read
    buf = ''.b
    loop do
      b1, b2 = @s.read(2).unpack('CC'); len = b2 & 0x7f
      len = @s.read(2).unpack1('n') if len == 126
      len = @s.read(8).unpack1('Q>') if len == 127
      buf << @s.read(len)
      return buf.force_encoding('UTF-8') if b1 & 0x80 != 0
    end
  end

  def call(meth, params = {})
    @n += 1; frame({ id: @n, method: meth, params: params }.to_json)
    loop { r = JSON.parse(read); return r if r['id'] == @n }
  end

  def eval(js)
    call('Runtime.evaluate', expression: js, returnByValue: true, awaitPromise: true).dig('result', 'result', 'value')
  end

  def close
    Net::HTTP.get(URI("http://127.0.0.1:#{PORT}/json/close/#{@id}")) rescue nil
  end
end

# 検索結果を下へ送りながら、動画付きの投稿だけ拾う
SCRAPE = <<~'JS'
  (async()=>{const sl=ms=>new Promise(r=>setTimeout(r,ms)); await sl(5000);
   if(/login|onboarding/.test(location.href)) return JSON.stringify({login:false,url:location.href});
   const seen=new Map();
   for(let k=0;k<SCROLL;k++){
     for(const a of document.querySelectorAll('article')){
       const link=[...a.querySelectorAll('a[href*="/status/"]')].map(x=>x.href).find(h=>/status\/\d+$/.test(h));
       if(!link||seen.has(link)) continue;
       const vid=!!a.querySelector('video, [data-testid="videoPlayer"], [data-testid="videoComponent"]');
       if(!vid) continue;
       const txt=((a.querySelector('[data-testid="tweetText"]')||{}).innerText||'').replace(/\n/g,' ');
       seen.set(link,{url:link,time:(a.querySelector('time')||{}).dateTime||'',text:txt.slice(0,140)});
     }
     window.scrollBy(0,2500); await sl(2000);
   }
   return JSON.stringify({login:true,url:location.href,items:[...seen.values()]});})()
JS

case cmd
# ---------------------------------------------------------------------------------------
when 'prep'
  src = rest.first or abort 'prep <参考動画のURL か mp4> --work DIR --from 秒 --to 秒'
  abort '--from と --to を付ける' unless opts[:from] && opts[:to]
  short = File.join(W, 'short.mp4')
  if File.file?(src)
    FileUtils.cp(src, short)
  else
    abort 'yt-dlp が見つからない' unless YT_BIN
    env = { 'PATH' => "#{YT_BIN}:/usr/bin:/bin" }
    yt = ["#{YT_BIN}/yt-dlp", '--no-warnings']
    # deno を明示しないと YouTube の署名が解けず、形式が一覧に出ない（Dog React の reference_rip.rb と同じ）
    yt += ['--js-runtimes', "deno:#{YT_BIN}/deno"] if File.executable?("#{YT_BIN}/deno")
    o, = Open3.capture2e(env, *yt, '-J', src)
    info = (JSON.parse(o.force_encoding('UTF-8')[/\{.*\}/m]) rescue {})
    meta['title'] = info['title']; meta['channel'] = info['channel']; meta['description'] = info['description']
    FileUtils.rm_f(short)
    Open3.capture2e(env, *yt, '-q', '-f', 'b[ext=mp4]/b', '-o', short, src)
    abort "落とせなかった: #{src}" unless File.size?(short)
  end
  meta['source'] = src; meta['from'] = opts[:from]; meta['to'] = opts[:to]; save_meta.call
  mid = (opts[:from] + opts[:to]) / 2
  ff('-ss', opts[:from].to_s, '-i', short, '-t', (opts[:to] - opts[:from]).to_s,
     '-vf', 'fps=1/2,scale=240:-2,tile=6x2', '-frames:v', '1', File.join(W, 'range.png'))
  ff('-ss', mid.to_s, '-i', short, '-frames:v', '1', File.join(W, 'frame.png'))
  o, = Open3.capture2e(FF, '-i', short)
  size = o.force_encoding('UTF-8')[/, (\d{2,5})x(\d{2,5})/] ? "#{$1}x#{$2}" : '?'
  puts "タイトル: #{meta['title']}" if meta['title']
  puts "チャンネル: #{meta['channel']}" if meta['channel']
  links = meta['description'].to_s.scan(%r{https?://\S+})
  puts "説明欄のリンク: #{links.join(' ')}" unless links.empty?
  puts "動画: #{short}（#{size}・#{duration(short).round(1)}秒）"
  puts "区間のコマ: #{File.join(W, 'range.png')}"
  puts "切り出し位置を決める1コマ（原寸）: #{File.join(W, 'frame.png')}"

# ---------------------------------------------------------------------------------------
when 'search'
  abort 'search --work DIR "<検索語>" ...' if rest.empty?
  abort "デバッグ Chrome（#{PORT}）が起動していない" unless (Net::HTTP.get(URI("http://127.0.0.1:#{PORT}/json/version")) rescue nil)
  cands = File.exist?(CANDS) ? JSON.parse(File.read(CANDS)) : []
  have = cands.map { |c| c['id'] }
  tab = Tab.new
  begin
    rest.each do |q0|
      break if cands.size >= opts[:limit]
      q = q0.dup
      q += ' filter:videos' unless q.include?('filter:videos')
      q += " since:#{opts[:since]}" if opts[:since] && !q.include?('since:')
      q += " until:#{opts[:until]}" if opts[:until] && !q.include?('until:')
      url = "https://x.com/search?q=#{URI.encode_www_form_component(q)}&src=typed_query&f=#{opts[:latest] ? 'live' : 'top'}"
      tab.call('Page.navigate', url: url)
      r = JSON.parse(tab.eval(SCRAPE.sub('SCROLL', opts[:scroll].to_s)) || '{}')
      if r['login'] == false
        abort "X にログインしていない（#{r['url']}）。デバッグ Chrome で X にログインし直してもらう。パスワードは入れない。"
      end
      added = 0
      (r['items'] || []).each do |i|
        id = i['url'][/status\/(\d+)/, 1]
        next if have.include?(id)
        break if cands.size >= opts[:limit]
        cands << i.merge('id' => id, 'query' => q0); have << id; added += 1
      end
      puts "#{q}  → #{(r['items'] || []).size} 件（新しく #{added} 件、計 #{cands.size}）"
    end
  ensure
    tab.close
  end
  File.write(CANDS, JSON.pretty_generate(cands))
  puts "上限 #{opts[:limit]} 本に達した" if cands.size >= opts[:limit]

# ---------------------------------------------------------------------------------------
when 'fetch'
  cands = JSON.parse(File.read(CANDS)) rescue abort('先に search を回す')
  pd = File.join(W, 'posts'); vd = File.join(W, 'videos'); FileUtils.mkdir_p([pd, vd])
  q = Queue.new; cands.each { |c| q << c }
  Array.new(8) {
    Thread.new {
      while (c = (q.pop(true) rescue nil))
        jp = File.join(pd, "#{c['id']}.json")
        unless File.size?(jp)
          body, = Open3.capture2('curl', '-s', '--max-time', '30', "https://api.fxtwitter.com/status/#{c['id']}")
          File.write(jp, body)
        end
        media = (JSON.parse(File.read(jp)).dig('tweet', 'media', 'all') rescue nil) || []
        media.select { |m| m['type'] == 'video' }.each_with_index do |m, i|
          vp = File.join(vd, "#{c['id']}_#{i + 1}.mp4")
          next if File.size?(vp)
          vs = (m['variants'] || []).select { |v| v['content_type'] == 'video/mp4' }.sort_by { |v| v['bitrate'].to_i }
          u = (vs[1] || vs[0] || {})['url'] || m['url']
          system('curl', '-sL', '--max-time', '120', u, '-o', vp) if u
        end
      end
    }
  }.each(&:join)
  puts "投稿 #{Dir[File.join(pd, '*.json')].size} 件・動画 #{Dir[File.join(vd, '*.mp4')].size} 本"

# ---------------------------------------------------------------------------------------
when 'match'
  short = File.join(W, 'short.mp4')
  abort '先に prep を回す' unless File.exist?(short) && meta['from']
  crop = opts[:crop] || meta['crop']
  meta['crop'] = crop; save_meta.call
  gw, gh = 24, 36
  frames = lambda do |path, vf, fps|
    raw, = Open3.capture2(FF, '-loglevel', 'error', '-i', path, '-vf', "fps=#{fps},#{vf},scale=#{gw}:#{gh},format=gray",
                          '-f', 'rawvideo', '-', binmode: true)
    raw.bytes.each_slice(gw * gh).select { |a| a.size == gw * gh }.map do |a|
      m = a.sum.to_f / a.size; d = a.map { |x| x - m }; n = Math.sqrt(d.map { |x| x * x }.sum); n = 1.0 if n.zero?
      d.map { |x| x / n }
    end
  end
  ncc = ->(a, b) { s = 0.0; a.each_index { |i| s += a[i] * b[i] }; s }
  cw, ch = crop ? crop.split(':').first(2).map(&:to_f) : [9.0, 16.0]
  ratio = cw / ch
  ref_vf = "trim=#{meta['from']}:#{meta['to']},setpts=PTS-STARTPTS" + (crop ? ",crop=#{crop}" : '')
  ref = frames.(short, ref_vf, 2)
  abort '区間のコマが取れない（--from/--to か --crop を見直す）' if ref.empty?
  # 候補は参考側と同じ縦横比に中央で切る。素材を少し拡大して使うことが多いので 1.0・0.87・0.75 の3通りを見る
  vids = Dir[File.join(W, 'videos', '*.mp4')].sort
  q = Queue.new; vids.each { |v| q << v }; res = []; mx = Mutex.new
  Array.new(6) {
    Thread.new {
      while (v = (q.pop(true) rescue nil))
        best = [1.0, 0.87, 0.75].map do |z|
          vf = "crop='min(iw,ih*#{ratio})*#{z}':'min(ih,iw/#{ratio})*#{z}'"
          c = frames.(v, vf, 2)
          next 0.0 if c.empty?
          s = ref.map { |r| c.map { |x| ncc.(r, x) }.max }.sort.reverse
          k = [6, s.size].min
          s.first(k).sum / k
        end.max
        mx.synchronize { res << [v, best] }
      end
    }
  }.each(&:join)
  res.sort_by! { |_, s| -s }
  rows = res.map do |v, s|
    id = File.basename(v)[/^(\d+)/, 1]
    t = (JSON.parse(File.read(File.join(W, 'posts', "#{id}.json")))['tweet'] rescue {}) || {}
    { 'score' => s.round(3), 'video' => v, 'url' => t['url'] || "https://x.com/i/status/#{id}",
      'date' => JST.(t['created_at']), 'likes' => t['likes'], 'views' => t['views'],
      'text' => t['text'].to_s.gsub(/\s+/, ' ')[0, 90] }
  end
  File.write(File.join(W, 'ranking.json'), JSON.pretty_generate(rows))
  hit = rows.select { |r| r['score'] >= MATCH }
  top = hit.empty? ? rows.first(opts[:top] * 2) : hit
  puts hit.empty? ? "一致なし（#{MATCH} 以上が無い）。一致度の高い順:" : "一致（#{MATCH} 以上）:"
  top.each_with_index { |r, i| puts "#{i + 1}. #{r['score']}  #{r['url']}  #{r['date']}  ♥#{r['likes']}\n     #{r['text']}" }
  puts "（照合 #{vids.size} 本。上位は #{opts[:top] * 2} 件まで出している。別公演・別グループの投稿を目で外して #{opts[:top]} 本にする）" if hit.empty?
  # 見比べ用：1段目が参考の区間、2段目以降が上位の候補
  strip = lambda do |src, vf, out|
    d = src == short ? meta['to'] - meta['from'] : duration(src)
    fps = d > 0 ? (8.0 / d).round(4) : 1
    ff('-i', src, '-vf', "#{vf}fps=#{fps},scale=110:196:force_original_aspect_ratio=decrease,pad=110:196:(ow-iw)/2:(oh-ih)/2,tile=8x1",
       '-frames:v', '1', out)
  end
  tmp = File.join(W, 'strips'); FileUtils.mkdir_p(tmp)
  files = [File.join(tmp, '0.png')]
  strip.(short, "#{ref_vf},", files[0])
  top.first(opts[:top] * 2).each_with_index do |r, i|
    f = File.join(tmp, "#{i + 1}.png"); files << f if strip.(r['video'], '', f)
  end
  ff(*files.flat_map { |f| ['-i', f] }, '-filter_complex', "vstack=inputs=#{files.size}", File.join(W, 'top.png')) if files.size > 1
  puts "見比べ: #{File.join(W, 'top.png')}（1段目が参考の区間、以下は上の順）"

else
  puts <<~USAGE
    ruby find_source.rb prep   "<参考動画URL|mp4>" --work DIR --from 秒 --to 秒
    ruby find_source.rb search --work DIR [--since YYYY-MM-DD --until YYYY-MM-DD] [--limit 100] [--latest] "<検索語>" ...
    ruby find_source.rb fetch  --work DIR
    ruby find_source.rb match  --work DIR [--crop W:H:X:Y] [--top 5]
  USAGE
end
