#!/usr/bin/env python3
"""画像にモザイクをかける。

例:
  python3 mosaic.py in.jpg out.jpg --box 990,1160,1170,1470      # 指定範囲だけ
  python3 mosaic.py in.jpg out.jpg --box 0,0,100,100 --box 200,200,300,300 --block 20
  python3 mosaic.py in.jpg out.jpg                                # 範囲なし = 画像全体
"""
import argparse

from PIL import Image


def mosaic(im, box, block):
    region = im.crop(box)
    w, h = region.size
    small = region.resize((max(1, w // block), max(1, h // block)), Image.NEAREST)
    im.paste(small.resize((w, h), Image.NEAREST), box)


def parse_box(s):
    x1, y1, x2, y2 = (int(v) for v in s.split(","))
    return (x1, y1, x2, y2)


def main():
    p = argparse.ArgumentParser(description="画像にモザイクをかける")
    p.add_argument("input")
    p.add_argument("output")
    p.add_argument("--box", type=parse_box, action="append",
                   help="x1,y1,x2,y2 (複数指定可。省略時は画像全体)")
    p.add_argument("--block", type=int, default=15, help="モザイクの粗さ(px)")
    args = p.parse_args()

    im = Image.open(args.input).convert("RGB")
    for box in args.box or [(0, 0) + im.size]:
        mosaic(im, box, args.block)
    im.save(args.output, quality=92)


if __name__ == "__main__":
    main()
