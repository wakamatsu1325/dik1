#!/usr/bin/env python3
"""Lark 公開ドキュメントを PDF にする。使い方: lark_doc_pdf.py <URL> <出力ディレクトリ>"""
import html, os, re, subprocess, sys, tempfile

URL, OUT = sys.argv[1], sys.argv[2]

JS = r"""
const { chromium } = require('playwright');
const fs = require('fs');
const [url, outdir] = process.argv.slice(2);
(async () => {
  const b = await chromium.launch({executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox']});
  const p = await b.newPage({viewport: {width: 1000, height: 1400}});
  await p.goto(url, {waitUntil: 'domcontentloaded', timeout: 90000});
  await p.waitForTimeout(10000);
  await p.evaluate(() => { document.querySelector('.bear-web-x-container').setAttribute('data-sc', '1'); window.__blocks = {}; });
  const snap = () => p.evaluate(() => {
    for (const e of document.querySelectorAll('[data-block-id]')) {
      const id = +e.getAttribute('data-block-id'); if (isNaN(id) || id === 1) continue;
      if (e.parentElement.closest('[data-block-id]:not([data-block-id="1"])')) continue;
      const prev = window.__blocks[id]; if (prev && prev.ok) continue;
      const c = e.cloneNode(true), ci = [...c.querySelectorAll('img')], oi = [...e.querySelectorAll('img')];
      let ok = true;
      ci.forEach((t, k) => {
        const im = oi[k];
        if (im.naturalWidth < 50 || !im.complete) { ok = false; return; }
        try { const cv = document.createElement('canvas'); cv.width = im.naturalWidth; cv.height = im.naturalHeight;
          cv.getContext('2d').drawImage(im, 0, 0); t.src = cv.toDataURL('image/jpeg', 0.9); t.removeAttribute('srcset'); } catch (x) { ok = false; }
      });
      window.__blocks[id] = {html: c.outerHTML, ok: ok || ci.length === 0};
    }
  });
  for (let i = 0; i < 200; i++) {
    await snap();
    const done = await p.evaluate(() => { const e = document.querySelector('[data-sc]'); e.scrollTop += 500; return e.scrollTop + e.clientHeight >= e.scrollHeight - 5; });
    await p.waitForTimeout(1200);
    if (done && i > 3) break;
  }
  await p.waitForTimeout(2000); await snap();
  const blocks = await p.evaluate(() => window.__blocks);
  const ids = Object.keys(blocks).map(Number).sort((a, b) => a - b);
  console.error('blocks', ids.length, 'notok', ids.filter(i => !blocks[i].ok).length);
  const title = (await p.title()).replace(/ - Lark Docs$/, '');
  fs.writeFileSync(outdir + '/title.txt', title);
  fs.writeFileSync(outdir + '/body.html', ids.map(i => blocks[i].html).join('\n'));
  await b.close();
})();
"""

PRINT = r"""
const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch({executablePath: '/opt/pw-browsers/chromium', args: ['--no-sandbox']});
  const p = await b.newPage();
  await p.goto('file://' + process.argv[2]);
  await p.waitForTimeout(1500);
  await p.pdf({path: process.argv[3], format: 'A4', margin: {top: '15mm', bottom: '15mm', left: '12mm', right: '12mm'}, printBackground: true});
  await b.close();
})();
"""

CSS = """body{font-family:sans-serif;max-width:800px;margin:20px auto;font-size:15px;line-height:1.7}
h1{font-size:28px}img{max-width:100%;max-height:200mm;width:auto!important;height:auto!important;object-fit:contain}
.image-block-width-wrapper,.image-block-container{width:auto!important;max-width:100%!important;padding-top:0!important;height:auto!important}
.resizable-wrapper,.resizable-wrapper *{position:static!important;width:auto!important;height:auto!important;max-width:100%}
.docx-image-block{break-inside:avoid;margin:8px 0}
.docx-text-block.isEmpty{min-height:0!important;height:0.6em}
.docx-block-zero-space{display:none}"""

env = dict(os.environ, NODE_PATH=subprocess.check_output(['npm', 'root', '-g'], text=True).strip())
with tempfile.TemporaryDirectory() as td:
    for name, src in (('collect.js', JS), ('print.js', PRINT)):
        open(f'{td}/{name}', 'w').write(src)
    subprocess.run(['node', f'{td}/collect.js', URL, td], check=True, env=env)
    title = open(f'{td}/title.txt').read().strip() or 'lark-doc'
    body = open(f'{td}/body.html').read()
    open(f'{td}/doc.html', 'w').write(
        f'<!doctype html><meta charset=utf-8><title>{html.escape(title)}</title><style>{CSS}</style><h1>{html.escape(title)}</h1>{body}')
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, re.sub(r'[\\/:*?"<>|]', '_', title) + '.pdf')
    subprocess.run(['node', f'{td}/print.js', f'{td}/doc.html', out], check=True, env=env)
print(out)
