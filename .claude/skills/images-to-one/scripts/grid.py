#!/usr/bin/env python3
"""画像を1枚のグリッドにまとめる。使い方: grid.py OUT.jpg IMG1 IMG2 ... [--cols N] [--cell-w 780]"""
import sys, argparse
from PIL import Image
p = argparse.ArgumentParser()
p.add_argument('out'); p.add_argument('imgs', nargs='+')
p.add_argument('--cols', type=int, default=4)
p.add_argument('--cell-w', type=int, default=780)
a = p.parse_args()
ims = [Image.open(f).convert('RGB') for f in a.imgs]
w = a.cell_w
h = round(ims[0].height * w / ims[0].width)
cols = min(a.cols, len(ims)); rows = -(-len(ims) // cols)
c = Image.new('RGB', (w * cols, h * rows), 'white')
for i, im in enumerate(ims):
    c.paste(im.resize((w, h), Image.LANCZOS), ((i % cols) * w, (i // cols) * h))
c.save(a.out, quality=92)
print(a.out, c.size)
