#!/usr/bin/env python3
"""X の記事（x.com/i/article/...）を PDF にする。
使い方: python3 x_article_pdf.py <ポストURL または 記事URL> <出力フォルダ>
ログイン・APIキー不要。FxTwitter の公開API、curl、Chromium だけを使う。"""
import sys, os, re, json, glob, html, shutil, subprocess, tempfile, datetime

JST = datetime.timezone(datetime.timedelta(hours=9))
CSS = """
body{font-family:"Noto Sans CJK JP",sans-serif;font-size:11pt;line-height:1.8;margin:0}
h1{font-size:20pt}h2{font-size:15pt;border-bottom:1px solid #999;padding-top:8px}
p{margin:.6em 0}.meta{color:#333}
img.fig{max-width:100%;max-height:230mm;display:block;margin:8px auto;page-break-inside:avoid}
pre{white-space:pre-wrap;word-break:break-all;background:#f3f3f3;padding:8px;font-size:9.5pt;page-break-inside:avoid}
.cap{display:block;text-align:center;color:#555;font-size:9.5pt;font-style:italic}
.tw{border:1px solid #ccc;border-radius:12px;padding:12px 14px;margin:12px 0;page-break-inside:avoid;font-size:10.5pt;line-height:1.6}
.tw .h{display:flex;gap:10px;align-items:center}.tw .av{width:40px;height:40px;border-radius:50%}
.g{color:#666;font-size:9.5pt}.m{margin-top:8px}.tw p{margin:8px 0}
.vid{position:relative;width:fit-content;max-width:55%;margin:6px auto}.vid img{max-height:110mm;border-radius:10px;display:block;margin:0 auto}
.play{position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);font-size:34pt;color:#fff;background:#0009;border-radius:50%;width:60px;height:60px;line-height:60px;text-align:center}
.dur{position:absolute;right:8px;bottom:8px;background:#000b;color:#fff;font-size:9pt;padding:1px 6px;border-radius:4px}
.ph{max-width:60%;display:block;margin:6px auto;border-radius:10px}
.q{border:1px solid #ddd;border-radius:10px;padding:8px 10px;margin-top:8px}
"""
e = html.escape

def curl(url, out=None):
    cmd = ['curl', '-sSfL', '-m', '60', url] + (['-o', out] if out else [])
    r = subprocess.run(cmd, capture_output=True, check=True)
    return r.stdout

def api(sid):
    return json.loads(curl(f'https://api.fxtwitter.com/i/status/{sid}'))['tweet']

def data_uri(url, tmp, name):
    p = os.path.join(tmp, name); curl(url, p)
    import base64
    return 'data:image/jpeg;base64,' + base64.b64encode(open(p, 'rb').read()).decode()

def when(s):
    for f in ('%a %b %d %H:%M:%S %z %Y', '%Y-%m-%dT%H:%M:%S.%f%z'):
        try: return datetime.datetime.strptime(s, f).astimezone(JST)
        except ValueError: pass
    raise ValueError(s)

def card(sid, tmp):
    t = api(sid); a = t['author']; n = lambda x: f'{x:,}'
    th = ''
    media = t.get('media') or {}
    for i, v in enumerate(media.get('videos', [])):
        d = int(v['duration'])
        th += f'<div class="vid"><img src="{data_uri(v["thumbnail_url"], tmp, f"{sid}v{i}")}"><span class="play">▶</span><span class="dur">{d//60}:{d%60:02d}</span></div>'
    for i, p in enumerate(media.get('photos', [])):
        th += f'<img class="ph" src="{data_uri(p["url"], tmp, f"{sid}p{i}")}">'
    q = ''
    if t.get('quote'):
        Q = t['quote']; qa = Q['author']
        if Q.get('article'):
            ar = Q['article']
            body = f'<b>{e(ar["title"])}</b><br><span class="g">X記事 / {e(ar.get("preview_text","")[:120])}</span>'
        else:
            body = e(Q['text']).replace('\n', '<br>')
        q = f'<div class="q"><b>{e(qa["name"])}</b> <span class="g">@{e(qa["screen_name"])}</span><br>{body}</div>'
    d = when(t['created_at'])
    return (f'<div class="tw"><div class="h"><img class="av" src="{data_uri(a["avatar_url"], tmp, f"{sid}a")}">'
            f'<div><b>{e(a["name"])}</b><br><span class="g">@{e(a["screen_name"])}</span></div></div>'
            f'<p>{e(t["text"]).replace(chr(10), "<br>")}</p>{th}{q}'
            f'<div class="g m">{d:%Y/%m/%d %H:%M} · {n(t["views"])} 件の表示 ・ 返信 {n(t["replies"])} ・ リポスト {n(t["retweets"])} ・ いいね {n(t["likes"])} ・ ブックマーク {n(t["bookmarks"])}<br>{e(t["url"])}</div></div>')

def find_chrome():
    for p in sorted(glob.glob('/opt/pw-browsers/chromium-*/chrome-linux*/chrome')) + \
             ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome']:
        if os.path.exists(p): return p
    for n in ('chromium', 'google-chrome', 'chrome'):
        if shutil.which(n): return shutil.which(n)
    sys.exit('Chromium/Chrome が見つからない')

def ensure_font():
    if 'Noto Sans CJK JP' in subprocess.run(['fc-list', ':lang=ja', 'family'], capture_output=True, text=True).stdout:
        return
    subprocess.run('apt-get update -qq && apt-get install -y -qq fonts-noto-cjk', shell=True)

def main(url, outdir):
    m = re.search(r'status/(\d+)', url)
    if not m: sys.exit('ポストURL（x.com/…/status/数字）を渡す。x.com/i/article/… だけでは記事を引けない')
    t = api(m.group(1)); a = t.get('article')
    if not a: sys.exit('このポストに記事が付いていない')
    c = a['content']; ents = c['entityMap']
    ents = {int(k['key']): k['value'] for k in ents} if isinstance(ents, list) else {int(k): v for k, v in ents.items()}
    media = {x['media_id']: x['media_info'].get('original_img_url') for x in a['media_entities']}
    ensure_font()
    with tempfile.TemporaryDirectory() as tmp:
        B = [f'<h1>{e(a["title"])}</h1>',
             f'<p class="meta">著者: {e(t["author"]["name"])} (@{e(t["author"]["screen_name"])})<br>'
             f'元URL: {e(t["url"])}<br>投稿日: {when(a["created_at"]):%Y/%m/%d %H:%M}</p>']
        for b in c['blocks']:
            ty, x = b['type'], b['text']
            if ty == 'header-two': B.append(f'<h2>{e(x)}</h2>')
            elif ty == 'atomic':
                en = ents.get(b['entityRanges'][0]['key']) if b['entityRanges'] else None
                if not en: continue
                d = en['data']
                if en['type'] == 'MEDIA':
                    for mi in d['mediaItems']:
                        u = media.get(mi['mediaId'])
                        if u:
                            B.append(f'<img class="fig" src="{data_uri(u + "?name=orig", tmp, mi["mediaId"])}">')
                            if d.get('caption'): B.append(f'<span class="cap">{e(d["caption"])}</span>')
                elif en['type'] == 'MARKDOWN':
                    code = re.sub(r'^```[^\n]*\n|\n?```\s*$', '', d['markdown'])
                    B.append(f'<pre>{e(code)}</pre>')
                elif en['type'] == 'TWEET': B.append(card(d['tweetId'], tmp))
            else: B.append(f'<p>{e(x)}</p>')
        doc = f'<!doctype html><meta charset="utf-8"><style>{CSS}</style>' + '\n'.join(B)
        hp = os.path.join(tmp, 'a.html'); open(hp, 'w').write(doc)
        os.makedirs(outdir, exist_ok=True)
        name = re.sub(r'[/\\:*?"<>|]', '_', a['title']).strip() + '.pdf'
        out = os.path.join(outdir, name)
        subprocess.run([find_chrome(), '--headless', '--no-sandbox', '--disable-gpu', '--no-pdf-header-footer',
                        f'--print-to-pdf={out}', 'file://' + hp], capture_output=True, check=True)
    print(f'保存: {out}（{os.path.getsize(out)//1024}KB）')

if __name__ == '__main__':
    if len(sys.argv) != 3: sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
