#!/usr/bin/env python3
"""note の下書きプレビュー（note.com/preview/n…?prev_access_key=…）を PDF にする。
使い方: note_preview_pdf.py "<プレビューURL>" <出力ディレクトリ>
公開APIは bad access になるが、ブラウザのUser-Agent付きの Chromium で開けば本文が描画される。
その描画後のDOMから本文・画像を拾う。投稿日は日本時間（<time datetime> の値）で書く。"""
import sys, re, os, html, glob, subprocess, tempfile
from datetime import datetime, timezone, timedelta

UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36'

def find_chrome():
    for p in sorted(glob.glob('/opt/pw-browsers/chromium-*/chrome-linux*/chrome')) + \
             ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome']:
        if os.path.exists(p): return p
    sys.exit('Chromium が見つからない')

def main(url, outdir):
    chrome = find_chrome()
    s = subprocess.run([chrome, '--headless', '--no-sandbox', '--disable-gpu', '--virtual-time-budget=25000',
                        f'--user-agent={UA}', '--dump-dom', url], capture_output=True, text=True, timeout=180).stdout
    t = re.search(r'<h1 class="o-noteContentHeader__title"[^>]*>(.*?)</h1>', s, re.S)
    if not t: sys.exit('本文が取れない（キーが無効か、ページ構造が変わった）')
    title = html.unescape(re.sub(r'<[^>]+>', '', t.group(1))).strip()
    au = re.search(r'<a href="/[^"]+" class="a-link"[^>]*>\s*([^<\s][^<]*?)\s*</a>', s)
    author = html.unescape(au.group(1)) if au else ''
    d = re.search(r'<time datetime="([^"]+)"', s)
    jst = datetime.fromisoformat(d.group(1)).astimezone(timezone(timedelta(hours=9)))
    posted = f'{jst.year}年{jst.month}月{jst.day}日 {jst:%H:%M}'
    a = s.find('<div data-name="body"'); a = s.find('>', a) + 1
    x = s[a:s.find('</article>', a)]
    depth = 1
    for m in re.finditer(r'<div\b|</div>', x):
        depth += 1 if m.group(0) == '<div' else -1
        if depth == 0: x = x[:m.start()]; break
    x = re.sub(r' style="[^"]*"', '', x)
    x = re.sub(r'<svg.*?</svg>|<button.*?</button>|<script.*?</script>', '', x, flags=re.S)
    w = tempfile.mkdtemp(); os.makedirs(f'{w}/img'); n = [0]
    def get(m):
        u = html.unescape(m.group(1)).split('?')[0]; n[0] += 1
        fn = f'img/{n[0]:02d}{os.path.splitext(u)[1] or ".jpg"}'
        subprocess.run(['curl', '-sSfL', '-m', '60', '-o', f'{w}/{fn}', u], check=True)
        return f'<img src="{fn}">'
    x = re.sub(r'<a [^>]*>(<img [^>]*>)</a>', r'\1', x)
    x = re.sub(r'<img [^>]*?src="(https://assets[^"]+)"[^>]*>', get, x)
    base = url.split('?')[0]
    doc = f'''<!doctype html><meta charset=utf-8><style>
body{{font-family:"Noto Sans CJK JP","Noto Sans JP","IPAGothic",sans-serif;font-size:11pt;line-height:1.9;color:#222;max-width:700px;margin:auto}}
h1{{font-size:20pt;line-height:1.4}}h2{{font-size:15pt;border-bottom:2px solid #ddd;padding-top:10px}}h3{{font-size:12.5pt}}
img{{max-width:100%;display:block;margin:10px auto}}figure{{margin:12px 0}}figcaption{{font-size:9pt;color:#666;text-align:center}}
.meta{{font-size:9pt;color:#555}}blockquote{{border-left:4px solid #ccc;margin:8px 0;padding-left:12px;color:#444}}
hr{{border:0;border-top:1px solid #ccc}}</style>
<h1>{html.escape(title)}</h1>
<div class=meta>{html.escape(author)}<br>{html.escape(base)}<br>{posted}<br>（公開前プレビュー画面）</div>{x}'''
    open(f'{w}/a.html', 'w').write(doc)
    name = re.sub(r'[/\\:*?"<>|]', '_', title) + '.pdf'
    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, name)
    subprocess.run([chrome, '--headless', '--no-sandbox', '--disable-gpu', '--no-pdf-header-footer',
                    f'--print-to-pdf={out}', f'file://{w}/a.html'], capture_output=True)
    print(f'{name}  画像{n[0]}枚  {posted}')

if __name__ == '__main__':
    if len(sys.argv) != 3: sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
