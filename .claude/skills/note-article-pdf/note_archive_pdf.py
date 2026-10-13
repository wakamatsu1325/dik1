#!/usr/bin/env python3
"""archive.li / archive.today で保存された note 記事の HTML（ブラウザで「ページを保存」したもの）を PDF にする。
使い方: note_archive_pdf.py <保存したhtml> <出力ディレクトリ>
画像は HTML 内の currentsourceurl（assets.st-note.com）から curl で取り直す。"""
import sys, re, os, subprocess, tempfile, html, glob

def find_chrome():
    for p in sorted(glob.glob('/opt/pw-browsers/chromium-*/chrome-linux*/chrome')) + \
             ['/Applications/Google Chrome.app/Contents/MacOS/Google Chrome']:
        if os.path.exists(p): return p
    for n in ('chromium', 'google-chrome', 'chrome'):
        for d in os.environ['PATH'].split(':'):
            if os.path.exists(os.path.join(d, n)): return os.path.join(d, n)
    sys.exit('Chromium が見つからない')

def main(src, outdir):
    s = open(src, encoding='utf-8', errors='replace').read()
    m = re.search(r'saved from url=\(\d+\)https://archive\.\w+/([\d.\-]+)/(\S+?)\s*-->', s)
    orig, stamp = (m.group(2), m.group(1)) if m else ('', '')
    a, b = s.find('<article'), s.find('</article>')
    x = s[a:b]
    x = re.sub(r' style="[^"]*"', '', x)
    x = re.sub(r'<svg.*?</svg>', '', x, flags=re.S)
    title = html.unescape(re.sub(r'<[^>]+>', '', re.search(r'<h1[^>]*>(.*?)</h1>', x, re.S).group(1))).strip()
    author = re.search(r'<a href="https://archive\.\w+/o/\w+/https://note\.com/[^"]+"[^>]*>\s*([^<\s][^<]*?)\s*</a>', x)
    author = html.unescape(author.group(1)) if author else ''
    t = re.search(r'<time[^>]*>(.*?)</time>', x, re.S)
    posted = re.sub(r'\s+', ' ', t.group(1)).strip() if t else ''
    hero = re.search(r'<img currentsourceurl="([^"]+)" alt="見出し画像"', x)
    start = x.find('<div id="', t.end() if t else 0)
    end = x.find('この記事が気に入ったら')
    end = x.rfind('<div><div><div><span>', 0, end) if end > 0 else len(x)
    body = x[start:end]
    body = re.sub(r'<button.*?</button>', '', body, flags=re.S)
    body = body.replace('&amp;nbsp;', '&nbsp;')
    w = tempfile.mkdtemp(); os.makedirs(f'{w}/img')
    n = [0]
    def get(full, name=None):
        url = full.split('?')[0]; n[0] += 1
        fn = name or f'img/{n[0]:02d}{os.path.splitext(url)[1] or ".jpg"}'
        if subprocess.run(['curl', '-sSfL', '-m', '60', '-o', f'{w}/{fn}', url]).returncode:
            subprocess.run(['curl', '-sSfL', '-m', '60', '-o', f'{w}/{fn}', full])
        return fn
    body = re.sub(r'<a [^>]*>(<img currentsourceurl="[^"]+"[^>]*>)</a>', r'\1', body)
    body = re.sub(r'<img currentsourceurl="([^"]+)"[^>]*>', lambda m: f'<img src="{get(m.group(1))}">', body)
    body = re.sub(r'<a [^>]*href="https://archive\.\w+/o/\w+/([^"]+)"[^>]*>', r'<a href="\1">', body)
    heroimg = f'<img src="{get(hero.group(1), "img/hero.jpg")}">' if hero else ''
    note = f'（公開前プレビュー画面を archive.li が {stamp} に保存したもの）' if stamp else ''
    doc = f'''<!doctype html><meta charset=utf-8><style>
body{{font-family:"Noto Sans CJK JP","Noto Sans JP","IPAGothic",sans-serif;font-size:11pt;line-height:1.9;color:#222;max-width:700px;margin:auto}}
h1{{font-size:20pt;line-height:1.4}}h2{{font-size:15pt;border-bottom:2px solid #ddd;padding-top:10px}}h3{{font-size:12.5pt}}
img{{max-width:100%;display:block;margin:10px auto}}figure{{margin:12px 0}}figcaption{{font-size:9pt;color:#666;text-align:center}}
.meta{{font-size:9pt;color:#555}}blockquote{{border-left:4px solid #ccc;margin:8px 0;padding-left:12px;color:#444}}
pre{{background:#f4f4f4;padding:8px;white-space:pre-wrap}}hr{{border:0;border-top:1px solid #ccc}}</style>
<h1>{html.escape(title)}</h1>
<div class=meta>{html.escape(author)}<br>{html.escape(orig)}<br>{html.escape(posted)}<br>{html.escape(note)}</div>
{heroimg}{body}'''
    open(f'{w}/a.html', 'w').write(doc)
    name = re.sub(r'[/\\:*?"<>|]', '_', title) + '.pdf'
    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, name)
    subprocess.run([find_chrome(), '--headless', '--no-sandbox', '--disable-gpu', '--no-pdf-header-footer',
                    f'--print-to-pdf={out}', f'file://{w}/a.html'], capture_output=True)
    print(f'{name}  画像{n[0]}枚  {posted}')

if __name__ == '__main__':
    if len(sys.argv) != 3: sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
