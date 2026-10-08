#!/usr/bin/env python3
"""note.com の記事を PDF にする。
使い方: python3 note_article_pdf.py <note.com/ユーザー/n/記事キー のURL> <出力フォルダ>
ログイン・APIキー不要（無料公開部分のみ）。curl、Chromium だけを使う。"""
import sys, os, re, json, glob, html, shutil, subprocess, tempfile, datetime, base64

JST = datetime.timezone(datetime.timedelta(hours=9))
CSS = """
body{font-family:"Noto Sans CJK JP",sans-serif;font-size:11pt;line-height:1.8;margin:0}
h1{font-size:20pt}h2{font-size:15pt;border-bottom:1px solid #999;padding-top:8px}h3{font-size:12.5pt}
p{margin:.6em 0}.meta{color:#333}
img.fig{max-width:100%;max-height:230mm;display:block;margin:8px auto;page-break-inside:avoid}
pre{white-space:pre-wrap;word-break:break-all;background:#f3f3f3;padding:8px;font-size:9.5pt;page-break-inside:avoid}
blockquote{border-left:4px solid #ccc;margin:.6em 0;padding:0 12px;color:#444}
.cap{display:block;text-align:center;color:#555;font-size:9.5pt;font-style:italic}
.ext{border:1px solid #ccc;border-radius:10px;padding:10px 14px;margin:10px 0;page-break-inside:avoid;font-size:10.5pt;line-height:1.5}
.ext em{display:block;font-style:normal;color:#666;font-size:9.5pt}.ext .u{word-break:break-all;color:#666;font-size:8.5pt}
"""
e = html.escape

def curl(url, out=None):
    cmd = ['curl', '-sSfL', '-m', '60', '-A', 'Mozilla/5.0', url] + (['-o', out] if out else [])
    return subprocess.run(cmd, capture_output=True, check=True).stdout

def data_uri(url, tmp, i):
    p = os.path.join(tmp, f'img{i}'); curl(url, p)
    return 'data:image/jpeg;base64,' + base64.b64encode(open(p, 'rb').read()).decode()

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

def clean(body, tmp):
    n = [0]
    def fig(m):
        s = m.group(0)
        if 'embedded-service' in s:
            t = re.findall(r'<(strong|em)>\s*(.*?)\s*</\1>', s, re.S)
            href = re.search(r'href="([^"]+)"', s)
            inner = ''.join(f'<{k}>{v}</{k}>' if k == 'em' else f'<div><b>{v}</b></div>' for k, v in t)
            return f'<div class="ext">{inner}<div class="u">{e(html.unescape(href.group(1))) if href else ""}</div></div>'
        im = re.search(r'<img[^>]*src="([^"]+)"', s)
        if not im: return ''
        n[0] += 1
        cap = re.search(r'<figcaption[^>]*>(.*?)</figcaption>', s, re.S)
        c = re.sub(r'<[^>]+>', '', cap.group(1)).strip() if cap else ''
        return f'<img class="fig" src="{data_uri(html.unescape(im.group(1)), tmp, n[0])}">' + (f'<span class="cap">{c}</span>' if c else '')
    body = re.sub(r'<figure.*?</figure>', fig, body, flags=re.S)
    body = re.sub(r'\s(name|id)="[^"]*"', '', body)
    return body

def main(url, outdir):
    m = re.search(r'/n/(n[0-9a-f]+)', url)
    if not m: sys.exit('note の記事URL（note.com/…/n/n英数字）を渡す')
    d = json.loads(curl(f'https://note.com/api/v3/notes/{m.group(1)}'))['data']
    paid = d.get('price') and not d.get('is_purchased') and d.get('paywall') is not None
    ensure_font()
    with tempfile.TemporaryDirectory() as tmp:
        dt = datetime.datetime.fromisoformat(d['publish_at']).astimezone(JST)
        B = [f'<h1>{e(d["name"])}</h1>',
             f'<p class="meta">著者: {e(d["user"]["nickname"])} (@{e(d["user"]["urlname"])})<br>'
             f'元URL: {e(d["note_url"])}<br>投稿日: {dt:%Y/%m/%d %H:%M}</p>']
        if d.get('eyecatch'): B.append(f'<img class="fig" src="{data_uri(d["eyecatch"], tmp, 0)}">')
        B.append(clean(d['body'], tmp))
        if paid: B.append('<p class="meta">※ 有料記事のため、無料公開部分のみ</p>')
        hp = os.path.join(tmp, 'a.html')
        open(hp, 'w').write(f'<!doctype html><meta charset="utf-8"><style>{CSS}</style>' + '\n'.join(B))
        os.makedirs(outdir, exist_ok=True)
        out = os.path.join(outdir, re.sub(r'[/\\:*?"<>|]', '_', d['name']).strip() + '.pdf')
        subprocess.run([find_chrome(), '--headless', '--no-sandbox', '--disable-gpu', '--no-pdf-header-footer',
                        f'--print-to-pdf={out}', 'file://' + hp], capture_output=True, check=True)
    print(f'保存: {out}（{os.path.getsize(out)//1024}KB）')

if __name__ == '__main__':
    if len(sys.argv) != 3: sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
