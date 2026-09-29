#!/usr/bin/env python3
"""Zoom into an image to locate a mosaic, then cover it with one solid rectangle.

Two subcommands:
  zoom  -- write an upscaled crop so you can SEE where the mosaic starts and ends
  mask  -- cover one or more regions with a single solid rectangle and save the result

Coordinates are always pixels in the ORIGINAL image, origin top-left, x1/y1 exclusive-ish
(the rectangle is drawn inclusive of the given edges, which is what you want for full cover).
"""

import argparse
import math
import os
import sys

from PIL import Image, ImageDraw

DEFAULT_COLOR = "#838383"


def parse_color(s):
    s = s.strip()
    if s.startswith("#"):
        s = s[1:]
    if len(s) == 3:
        s = "".join(c * 2 for c in s)
    if len(s) != 6:
        raise ValueError(f"色は #RRGGBB 形式で指定してください: {s}")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def cmd_zoom(args):
    im = Image.open(args.image).convert("RGB")
    W, H = im.size
    x0, y0, x1, y1 = args.box
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(W, x1), min(H, y1)
    crop = im.crop((x0, y0, x1, y1))
    scale = args.scale
    if scale is None:
        # Aim for roughly 700px on the long side: big enough to see block edges,
        # small enough to stay cheap to look at.
        scale = max(1, round(700 / max(crop.width, crop.height)))
    crop = crop.resize((crop.width * scale, crop.height * scale), Image.NEAREST)
    crop.save(args.out)
    print(f"crop=({x0},{y0})-({x1},{y1}) scale={scale}x -> {args.out}")
    print(f"元画像座標への換算: orig_x = {x0} + zoom_x/{scale}, orig_y = {y0} + zoom_y/{scale}")


def min_area_rect(points):
    """Smallest-area rectangle (rotation allowed) containing all points.

    Returns (area, angle_deg, corners). Rotating rarely helps for a single mosaic
    block, but when the covered regions form an L or a diagonal run it can shrink
    the mask noticeably -- so it is worth the quarter-degree sweep.
    """
    best = None
    for i in range(0, 360 * 4):
        deg = i / 4
        t = math.radians(deg)
        c, s = math.cos(t), math.sin(t)
        us = [x * c + y * s for x, y in points]
        vs = [-x * s + y * c for x, y in points]
        umin, umax, vmin, vmax = min(us), max(us), min(vs), max(vs)
        area = (umax - umin) * (vmax - vmin)
        if best is None or area < best[0] - 1e-9:
            best = (area, deg, umin, umax, vmin, vmax)
    area, deg, umin, umax, vmin, vmax = best
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)
    corners = [
        (u * c - v * s, u * s + v * c)
        for u, v in ((umin, vmin), (umax, vmin), (umax, vmax), (umin, vmax))
    ]
    return area, deg, corners


def cmd_mask(args):
    im = Image.open(args.image).convert("RGBA")
    color = parse_color(args.color)

    pts = []
    for x0, y0, x1, y1 in args.rect:
        pts += [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]

    d = ImageDraw.Draw(im)
    if args.keep_separate:
        for x0, y0, x1, y1 in args.rect:
            d.rectangle([x0, y0, x1, y1], fill=color)
        shape = f"{len(args.rect)} 個の長方形"
    else:
        area, deg, corners = min_area_rect(pts)
        d.polygon(corners, fill=color)
        rounded = ", ".join(f"({x:.0f},{y:.0f})" for x, y in corners)
        shape = f"1枚の長方形 角度{deg:g}° 面積{area:.0f}px² 頂点[{rounded}]"

    out = args.out
    if out is None:
        base = os.path.splitext(os.path.basename(args.image))[0]
        out = os.path.expanduser(f"~/Desktop/{base}_masked.png")
    im.save(out)
    print(f"{shape} / 色 {args.color} -> {out}")


def rect_arg(s):
    parts = [int(float(v)) for v in s.replace(",", " ").split()]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("長方形は 'x0 y0 x1 y1' の4値で指定してください")
    x0, y0, x1, y1 = parts
    return (min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    z = sub.add_parser("zoom", help="拡大クロップを書き出して目視確認する")
    z.add_argument("image")
    z.add_argument("--box", type=int, nargs=4, required=True, metavar=("X0", "Y0", "X1", "Y1"))
    z.add_argument("--scale", type=int, default=None, help="整数倍率。省略時は自動")
    z.add_argument("--out", default="/tmp/mosaic_zoom.png")
    z.set_defaults(func=cmd_zoom)

    m = sub.add_parser("mask", help="指定領域をまとめて単色の長方形で塗る")
    m.add_argument("image")
    m.add_argument("--rect", type=rect_arg, action="append", required=True,
                   help="'x0 y0 x1 y1'。複数指定すると全部を含む最小の長方形1枚にまとめる")
    m.add_argument("--color", default=DEFAULT_COLOR)
    m.add_argument("--out", default=None, help="省略時は ~/Desktop/<元の名前>_masked.png")
    m.add_argument("--keep-separate", action="store_true",
                   help="まとめずに指定した長方形をそれぞれ塗る（作業途中の確認用）")
    m.set_defaults(func=cmd_mask)

    args = p.parse_args()
    try:
        args.func(args)
    except Exception as e:
        print(f"エラー: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
