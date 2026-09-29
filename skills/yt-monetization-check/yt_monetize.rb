# frozen_string_literal: true
# YouTube チャンネルが収益化（YPP）しているかを外から判定する。
#   1) ログインなし（curl）：登録者・動画数・動画一覧、ショッピングのアフィリエイト表示
#   2) ログインあり（デバッグ Chrome 9333 を CDP で操作）：動画の「…」メニューに Thanks が出るか
# Thanks もアフィリエイトも YPP 加入が条件なので、どちらかが1本でも出れば「収益化済み（確定）」。
# 出なければ「Thanks 出ず」（切っているだけの可能性があるので未収益化とは言わない）。
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8
require 'json'; require 'open3'; require 'socket'; require 'net/http'
require 'securerandom'; require 'base64'; require 'uri'; require 'fileutils'

PORT = 9333
PROFILE = File.expand_path('~/.dog_imagine_chrome')
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128 Safari/537.36'

opts = { long: 3, shorts: 5, tabs: 3, out: nil, dirs: [], skip_thanks: false }
inputs = []
args = ARGV.map { |a| a.dup.force_encoding("UTF-8") } # LANG 無しだと ASCII-8BIT で来る
until args.empty?
  a = args.shift
  case a
  when '--long' then opts[:long] = args.shift.to_i
  when '--shorts' then opts[:shorts] = args.shift.to_i
  when '--tabs' then opts[:tabs] = args.shift.to_i
  when '--out' then opts[:out] = File.expand_path(args.shift)
  when '--community-dir' then opts[:dirs] << File.expand_path(args.shift)
  when '--no-thanks' then opts[:skip_thanks] = true
  else inputs << a
  end
end
nfc = ->(s) { s.to_s.unicode_normalize(:nfc) }

def get(url)
  3.times do
    o, st = Open3.capture2('curl', '-sL', '--max-time', '30', '-A', UA, '-H', 'Accept-Language: ja', '-b', 'CONSENT=YES+1', url)
    o = o.force_encoding('UTF-8').scrub
    return o if st.success? && o.size > 1000
    sleep 1
  end
  ''
end

def channel_id_from(page)
  page[/"externalId":"(UC[\w-]{22})"/, 1] || page[/"channelId":"(UC[\w-]{22})"/, 1] || page[/"browseId":"(UC[\w-]{22})"/, 1]
end

# ---- 対象を集める ----------------------------------------------------------
targets = [] # [表示名, 入力]
opts[:dirs].each do |dir|
  Dir.glob(File.join(dir, '*_投稿')).sort.each do |d|
    name = nfc.(File.basename(d).sub(/_投稿\z/, ''))
    post = Dir.glob(File.join(d, '*.txt')).map { |f| File.read(f)[%r{https://www\.youtube\.com/post/[\w-]+}] }.compact.first
    targets << [name, post] if post
  end
end
inputs.each { |i| targets << [nil, i] }
abort '対象がありません（チャンネルURL / @handle / UC… / 投稿URL、または --community-dir DIR）' if targets.empty?

def to_url(x)
  x = x.strip
  return "https://www.youtube.com/channel/#{x}" if x =~ /\AUC[\w-]{22}\z/
  return "https://www.youtube.com/#{x}" if x.start_with?('@')
  x = "https://#{x}" unless x =~ %r{\Ahttps?://}
  x.sub(%r{/(shorts|videos|posts|featured|streams|community)/?\z}, '')
end

$stderr.puts "対象 #{targets.size} チャンネル。ログインなしで一覧とアフィリエイトを見ます…"
q = Queue.new; targets.each { |t| q << t }
chans = {}; mx = Mutex.new
Array.new(6) { Thread.new {
  loop do
    name, src = (q.pop(true) rescue break)
    id = channel_id_from(get(to_url(src)))
    unless id
      mx.synchronize { chans[name || src] = { 'error' => 'チャンネルを特定できない（削除・URL違い）', 'src' => src } }
      next
    end
    top = get("https://www.youtube.com/channel/#{id}")
    title = nfc.(top[/<meta property="og:title" content="([^"]*)"/, 1])
    long = get("https://www.youtube.com/channel/#{id}/videos").scan(/"videoId":"([\w-]{11})"/).flatten.uniq.first(opts[:long])
    shorts = get("https://www.youtube.com/channel/#{id}/shorts").scan(/"videoId":"([\w-]{11})"/).flatten.uniq.first(opts[:shorts])
    aff = (long + shorts).select { |v| h = get("https://www.youtube.com/watch?v=#{v}"); h.include?('productsInVideoOverlayRenderer') && h.include?('affiliateDisclaimerText') }
    rec = { 'id' => id, 'title' => title, 'handle' => URI.decode_www_form_component(top[/"canonicalBaseUrl":"\/(@[^"]+)"/, 1].to_s),
            'subs' => top[/"content":"チャンネル登録者数 ([^"]+)"/, 1], 'videos' => top[/"content":"([0-9,万.]+) 本の動画"/, 1],
            'long' => long, 'shorts' => shorts, 'affiliate' => aff, 'thanks' => nil, 'checked' => [], 'errors' => [] }
    mx.synchronize { chans[name || title || id] = rec }
  end
} }.each(&:join)

# ---- デバッグ Chrome で Thanks ---------------------------------------------
class Tab
  attr_reader :id
  def initialize
    t = JSON.parse(Net::HTTP.start('127.0.0.1', PORT) { |h| h.send_request('PUT', '/json/new?about:blank') }.body)
    @id = t['id']; u = URI(t['webSocketDebuggerUrl'])
    @s = TCPSocket.new(u.host, u.port)
    @s.write("GET #{u.path} HTTP/1.1\r\nHost: #{u.host}:#{u.port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" \
             "Sec-WebSocket-Key: #{Base64.strict_encode64(SecureRandom.random_bytes(16))}\r\nSec-WebSocket-Version: 13\r\n\r\n")
    while (l = @s.gets) && l != "\r\n"; end
    @n = 0
    # 裏のタブはメニューが開かない・描かれないことがあるので、前面にあるものとして扱わせる
    call("Emulation.setFocusEmulationEnabled", enabled: true)
    call("Page.setWebLifecycleState", state: "active") rescue nil
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
    (Net::HTTP.get(URI("http://127.0.0.1:#{PORT}/json/close/#{@id}")) rescue nil)
  end
end

# watch?v= の形で開き、「その他の操作」を押してメニューを読む。ログインはアバターではなく ytcfg の LOGGED_IN で見る（アバターは描画が遅れて取りこぼす）。
PROBE = <<~'JS'
  (async()=>{const sl=ms=>new Promise(r=>setTimeout(r,ms));
   let more=null; for(let i=0;i<40&&!more;i++){await sl(500); more=[...document.querySelectorAll('ytd-watch-metadata button')].find(b=>/その他の操作/.test(b.getAttribute('aria-label')||''));}
   if(!location.href.includes(VID)) return JSON.stringify({err:'別のURLへ移った '+location.href});
   const signed=!!(window.ytcfg&&ytcfg.get('LOGGED_IN'));
   if(!more) return JSON.stringify({err:'メニューが出ない',signed});
   // 押してもメニューが開かないことがある（3回に1回ほど）。必ずある「報告」が読めるまで押し直す。
   const read=()=>[...document.querySelectorAll('tp-yt-iron-dropdown yt-list-item-view-model, tp-yt-iron-dropdown ytd-menu-service-item-renderer')].filter(e=>e.offsetParent).map(e=>e.innerText.trim().split('\n')[0]);
   let items=[];
   for(let t=0;t<3&&!items.includes('報告');t++){ await sl(800); more.click(); for(let i=0;i<8&&!items.includes('報告');i++){await sl(400); items=read();} if(!items.includes('報告')) document.body.click(); }
   // 項目は後から足される（Thanks が遅れて入る）ので、1秒変わらなくなるまで待つ
   for(let i=0,prev='',same=0;i<15&&same<2;i++){ await sl(500); items=read(); const k=items.join('|'); same = k===prev ? same+1 : 0; prev=k; }
   document.body.click();
   if(!items.includes('報告')) return JSON.stringify({err:'メニューが開かない',signed});
   return JSON.stringify({signed,menu:items});})()
JS

def chrome_alive?
  (Net::HTTP.get(URI("http://127.0.0.1:#{PORT}/json/version")) rescue nil)
end

need = chans.values.select { |c| c['id'] && c['affiliate'].empty? }
if !opts[:skip_thanks] && need.any?
  unless chrome_alive?
    $stderr.puts 'デバッグ Chrome が動いていないので起動します（~/.dog_imagine_chrome）'
    system('open', '-na', 'Google Chrome', '--args', "--remote-debugging-port=#{PORT}", "--user-data-dir=#{PROFILE}", '--no-first-run', '--no-default-browser-check')
    20.times { break if chrome_alive?; sleep 1 }
    abort 'デバッグ Chrome に繋がりません' unless chrome_alive?
  end
  $stderr.puts "デバッグ Chrome で Thanks を見ます（#{need.size} チャンネル、タブ #{opts[:tabs]} 枚）…"
  tabs = []; tmx = Mutex.new
  at_exit { tabs.each(&:close) } # 途中で止めてもタブを残さない
  trap('INT') { exit 130 }; trap('TERM') { exit 143 }
  q = Queue.new; need.each { |c| q << c }
  unsigned = false
  Array.new(opts[:tabs]) { Thread.new {
    tab = Tab.new; tmx.synchronize { tabs << tab }
    loop do
      break if unsigned
      c = (q.pop(true) rescue break)
      l = c['long'].dup; s = c['shorts'].dup; order = []
      order << l.shift << s.shift while l.any? || s.any?
      order = order.compact.uniq # 通常動画の無いチャンネルは /videos にショートが並ぶので重ねない
      order.each do |v|
        out = nil
        2.times do # 開かなかったら読み込みからやり直す
          tab.call('Page.navigate', url: "https://www.youtube.com/watch?v=#{v}")
          out = (JSON.parse(tab.eval(PROBE.sub('VID', v.to_json)) || '{"err":"応答なし"}') rescue { 'err' => $!.message })
          break unless out['err']
        end
        if out['err'] then c['errors'] << [v, out['err']]; next end
        unless out['signed'] then unsigned = true; c['errors'] << [v, 'ログインしていない']; break end
        c['checked'] << v
        if out['menu'].any? { |x| x =~ /Thanks/ } then c['thanks'] = v; break end
      end
      $stderr.puts "  #{c['title']}: #{c['thanks'] ? 'Thanks あり' : 'Thanks 出ず'}（#{c['checked'].size}本）"
    end
  } }.each(&:join)
  tabs.each(&:close); tabs.clear
  if unsigned
    warn 'デバッグ Chrome の YouTube がログアウトしています。だいきんぐにログインし直してもらってから、もう一度走らせてください。'
  end
end

# ---- まとめ ------------------------------------------------------------------
def subs_num(s)
  return -1 unless s
  n = s.delete(',').to_f
  s.include?('万') ? n * 10_000 : n
end
rows = chans.map do |name, c|
  verdict = if c['error'] then '取得失敗'
            elsif c['affiliate'].any? || c['thanks'] then '収益化済み（確定）'
            elsif opts[:skip_thanks] then '未判定（Thanks 未確認）'
            elsif c['checked'].empty? then '判定できず'
            else 'Thanks 出ず'
            end
  proof = c['thanks'] ? "Thanks #{c['thanks']}" : (c['affiliate'] && c['affiliate'].any? ? "アフィリエイト #{c['affiliate'].first}" : '')
  [name, c, verdict, proof]
end
rows.sort_by! { |_, c, v, _| [v.start_with?('収益化') ? 0 : 1, -subs_num(c['subs'])] }
puts "| チャンネル | 登録者 | 動画数 | 判定 | 根拠 | 見た本数 |"
puts '|---|---|---|---|---|---|'
rows.each do |name, c, v, proof|
  puts "| #{name} | #{c['subs'] || '-'} | #{c['videos'] || '-'} | #{v} | #{proof} | #{(c['checked'] || []).size} |"
end
ok = rows.count { |r| r[2].start_with?('収益化') }
puts "\n確定 #{ok} / #{rows.size}。Thanks 出ず #{rows.count { |r| r[2] == 'Thanks 出ず' }}、判定できず・失敗 #{rows.count { |r| r[2] =~ /判定できず|失敗/ }}"
errs = rows.select { |_, c, _, _| c['errors'] && c['errors'].any? }
errs.each { |name, c, _, _| puts "  注意 #{name}: " + c['errors'].map { |v, e| "#{v} #{e}" }.join(' / ') }
if opts[:out]
  FileUtils.mkdir_p(File.dirname(opts[:out]))
  File.write(opts[:out], JSON.pretty_generate(chans))
  puts "詳細: #{opts[:out]}"
end
