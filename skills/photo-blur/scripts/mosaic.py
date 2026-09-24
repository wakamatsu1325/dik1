#!/usr/bin/env python3
"""画像全面をモザイク（ブロック化）する。

手順は「原寸のままブロック平均 → 出力サイズへ縮小」。
ブロックの大きさは原本の横幅に比例させるので、解像度が変わっても見た目は変わらない。

  P1 (人物・強)     ブロック = 幅 x 1.30%
  M1 (建物の既定)   ブロック = 幅 x 0.91%
  P2 (人物の既定)   ブロック = 幅 x 0.90%

出力は原本の約 1/4（--scale 0.25）。この小ささも仕様の一部。
実測6組から同定。詳細は reference/calibration.md。
"""
import argparse, sys
from pathlib import Path
from PIL import Image, ImageOps

PRESETS = {"p1": 0.0130, "m1": 0.0091, "p2": 0.0090}
DEFAULT_SCALE = 0.25
DEFAULT_OUT = Path.home() / "Desktop"


def mosaic_one(src, pct, scale, outdir, tag, quality):
    im = ImageOps.exif_transpose(Image.open(src))
    if im.mode not in ("RGB", "L"):
        im = im.convert("RGB")
    B = max(1, round(pct * im.width))
    out = im.resize((max(1, im.width // B), max(1, im.height // B)), Image.BOX) \
            .resize(im.size, Image.NEAREST)
    if scale != 1.0:
        out = out.resize((max(1, round(im.width * scale)),
                          max(1, round(im.height * scale))), Image.LANCZOS)
    suffix = src.suffix if src.suffix.lower() in (".jpg", ".jpeg", ".png") else ".png"
    dst = outdir / f"mosaic_{tag}_{src.stem}{suffix}"
    if suffix.lower() in (".jpg", ".jpeg"):
        out.save(dst, quality=quality, subsampling=0)
    else:
        out.save(dst)
    print(f"{src.name}  {im.width}x{im.height} -> {out.width}x{out.height}  "
          f"ブロック {B}px ({pct*100:.2f}% of width) = 出力上 {B*scale:.1f}px  -> {dst}")
    return dst


def main():
    p = argparse.ArgumentParser(description="全面モザイク（ブロックは横幅比、出力は縮小込み）")
    p.add_argument("images", nargs="+", type=Path)
    p.add_argument("--level", choices=["p1", "m1", "p2"], default="p2",
                   help="プリセット (既定: p2 = 人物。建物は m1 を明示)")
    p.add_argument("--block-pct", type=float, default=None, metavar="PCT",
                   help="ブロックを横幅の百分率で直接指定 (例: 1.18)。--level より優先")
    p.add_argument("--scale", type=float, default=DEFAULT_SCALE,
                   help=f"出力の縮小率 (既定: {DEFAULT_SCALE})")
    p.add_argument("--out", type=Path, default=DEFAULT_OUT, help="出力先 (既定: ~/Desktop)")
    p.add_argument("--quality", type=int, default=95, help="JPEG 品質 (既定: 95)")
    a = p.parse_args()

    if a.block_pct is not None:
        pct, tag = a.block_pct / 100.0, f"PCT{a.block_pct:g}"
    else:
        pct, tag = PRESETS[a.level], a.level.upper()
    a.out.mkdir(parents=True, exist_ok=True)

    rc = 0
    for src in a.images:
        if not src.is_file():
            print(f"skip (not a file): {src}", file=sys.stderr); rc = 1; continue
        try:
            mosaic_one(src, pct, a.scale, a.out, tag, a.quality)
        except Exception as e:
            print(f"failed: {src}: {e}", file=sys.stderr); rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
