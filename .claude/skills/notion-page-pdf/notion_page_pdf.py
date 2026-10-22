#!/usr/bin/env python3
"""Notion 公開ページ(notion.site 等)を PDF にする。使い方: notion_page_pdf.py <URL> <出力ディレクトリ>

Chromium でページを開き、最後まで遅延読み込みさせ、1枚の縦長ページとして印刷する。
画像が重く 100MB を超えがちなので、PyMuPDF で画像を 110dpi に落とす。
"""
import os, re, subprocess, sys, tempfile

url, outdir = sys.argv[1], sys.argv[2]
os.makedirs(outdir, exist_ok=True)

JS = r"""
const { chromium } = require('playwright');
(async()=>{
const [url, out] = process.argv.slice(2);
const b = await chromium.launch({executablePath:'/opt/pw-browsers/chromium'});
const p = await b.newPage({viewport:{width:1000,height:1400}});
await p.goto(url,{waitUntil:'domcontentloaded',timeout:90000}); // networkidle は来ないので使わない
await p.waitForTimeout(8000);
await p.evaluate(async()=>{
  const s=document.querySelector('.notion-frame .notion-scroller')||document.querySelector('.notion-scroller');
  let last=-1;
  for(let i=0;i<300;i++){ s.scrollTop+=800; await new Promise(r=>setTimeout(r,400)); if(s.scrollTop===last)break; last=s.scrollTop;}
  await new Promise(r=>setTimeout(r,3000)); s.scrollTop=0;
});
await p.waitForTimeout(1500);
await p.addStyleTag({content:`
 .notion-topbar,.notion-topbar-mobile{display:none!important}
 html,body,#notion-app,.notion-app-inner,.notion-cursor-listener,.notion-frame,.notion-scroller{height:auto!important;overflow:visible!important;position:static!important}`});
await p.waitForTimeout(1500);
const h = await p.evaluate(()=>Math.max(document.body.scrollHeight,document.documentElement.scrollHeight));
console.log('TITLE='+await p.title());
await p.pdf({path:out,width:'1000px',height:Math.min(h+50,18000)+'px',printBackground:true});
await b.close();})();
"""
tmp = tempfile.mkdtemp()
js, raw = os.path.join(tmp, 'p.js'), os.path.join(tmp, 'raw.pdf')
open(js, 'w').write(JS)
env = dict(os.environ, NODE_PATH='/opt/node-tools/node_modules:/opt/node22/lib/node_modules')
r = subprocess.run(['node', js, url, raw], env=env, capture_output=True, text=True, timeout=600)
if r.returncode:
    sys.exit(r.stderr)
title = re.search(r'TITLE=(.*)', r.stdout).group(1).strip()
name = re.sub(r'[\\/:*?"<>|]', '_', title) or 'notion'

import pymupdf  # 無ければ pip install pymupdf
d = pymupdf.open(raw)
d.rewrite_images(dpi_threshold=130, dpi_target=110, quality=75)
dest = os.path.join(outdir, name + '.pdf')
d.save(dest, garbage=4, deflate=True)
mb = os.path.getsize(dest) / 1e6
print(f'{dest}  {mb:.1f}MB  {len(d)}ページ')
if mb > 100:
    print('警告: 100MB超。ユーザーに渡し方を確認する')
