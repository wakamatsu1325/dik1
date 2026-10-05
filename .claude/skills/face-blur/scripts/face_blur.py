#!/usr/bin/env python3
"""顔だけにガウシアンぼかしをかける。顔の位置は呼び出し側（Claude）が画像を見て楕円の外接矩形で渡す。

使い方:
  python3 face_blur.py 画像.jpg --box 535,470,815,800 --box 0,215,155,385 [--sigma 12] [--out DIR] [--name 元の名前]

--box x0,y0,x1,y1  ぼかす楕円の外接矩形（原寸ピクセル）。何個でも指定できる。
--sigma            ぼかしの強さ。既定12（弱め）。強め=28。
--feather          楕円の縁のなじませ。既定5。
--crop x0,y0,x1,y1 確認用に拡大した切り抜きも出す（任意）。
出力: <out>/blur_face_<入力名>.jpg（元ファイルは上書きしない）。
"""
import argparse, os, sys
from PIL import Image, ImageDraw, ImageFilter

p = argparse.ArgumentParser()
p.add_argument("src")
p.add_argument("--box", action="append", required=True)
p.add_argument("--sigma", type=float, default=12)
p.add_argument("--feather", type=float, default=5)
p.add_argument("--out", default=os.path.expanduser("~/Desktop"))
p.add_argument("--name")
p.add_argument("--crop")
p.add_argument("--quality", type=int, default=95)
a = p.parse_args()

im = Image.open(a.src).convert("RGB")
mask = Image.new("L", im.size, 0)
d = ImageDraw.Draw(mask)
for b in a.box:
    d.ellipse(tuple(int(float(v)) for v in b.split(",")), fill=255)
mask = mask.filter(ImageFilter.GaussianBlur(a.feather))
out = Image.composite(im.filter(ImageFilter.GaussianBlur(a.sigma)), im, mask)

os.makedirs(a.out, exist_ok=True)
name = a.name or os.path.splitext(os.path.basename(a.src))[0]
dst = os.path.join(a.out, f"blur_face_{name}.jpg")
out.save(dst, quality=a.quality)
print(dst, out.size)
if a.crop:
    x0, y0, x1, y1 = (int(v) for v in a.crop.split(","))
    c = out.crop((x0, y0, x1, y1))
    cp = os.path.join(a.out, f"blur_face_{name}_crop.jpg")
    c.resize((c.width * 2, c.height * 2)).save(cp, quality=90)
    print(cp)
