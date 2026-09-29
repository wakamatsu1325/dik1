#!/usr/bin/env python3
"""画像全面にガウシアンぼかしをかける。強度は元画像の横幅に比例させる。

  P1 (強) sigma = 幅 x 0.0060   顔の造作が完全に潰れる
  P2 (弱) sigma = 幅 x 0.0023   輪郭・表情は残る

実測サンプル5組から同定した値。詳細は reference/calibration.md。
"""
import argparse, sys
from pathlib import Path
from PIL import Image, ImageFilter, ImageOps

PRESETS = {"p1": 0.0060, "p2": 0.0023}
DEFAULT_OUT = Path.home() / "Desktop"


def blur_one(src, pct, outdir, tag, scale, quality):
    im = ImageOps.exif_transpose(Image.open(src))
    if im.mode not in ("RGB", "L"):
        im = im.convert("RGB")
    sigma = pct * im.width
    out = im.filter(ImageFilter.GaussianBlur(sigma))
    if scale != 1.0:
        out = out.resize((max(1, round(out.width * scale)),
                          max(1, round(out.height * scale))), Image.LANCZOS)
    suffix = src.suffix if src.suffix.lower() in (".jpg", ".jpeg", ".png") else ".png"
    dst = outdir / f"{src.stem}_{tag}{suffix}"
    if suffix.lower() in (".jpg", ".jpeg"):
        out.save(dst, quality=quality, subsampling=0)
    else:
        out.save(dst)
    print(f"{src.name}  {im.width}x{im.height}  sigma={sigma:.2f}px "
          f"({pct*100:.3f}% of width)  -> {dst}")
    return dst


def main():
    p = argparse.ArgumentParser(description="全面ガウシアンぼかし（強度は横幅比）")
    p.add_argument("images", nargs="+", type=Path)
    p.add_argument("--level", choices=sorted(PRESETS), default="p1",
                   help="プリセット強度 (既定: p1)")
    p.add_argument("--sigma-pct", type=float, default=None, metavar="PCT",
                   help="横幅に対する百分率で直接指定 (例: 0.45)。--level より優先")
    p.add_argument("--out", type=Path, default=DEFAULT_OUT,
                   help="出力先ディレクトリ (既定: ~/Desktop)")
    p.add_argument("--scale", type=float, default=1.0,
                   help="ぼかした後に縮小する倍率 (例: 0.37)")
    p.add_argument("--quality", type=int, default=95, help="JPEG 品質 (既定: 95)")
    a = p.parse_args()

    if a.sigma_pct is not None:
        pct, tag = a.sigma_pct / 100.0, f"blur{a.sigma_pct:g}"
    else:
        pct, tag = PRESETS[a.level], a.level
    a.out.mkdir(parents=True, exist_ok=True)

    rc = 0
    for src in a.images:
        if not src.is_file():
            print(f"skip (not a file): {src}", file=sys.stderr); rc = 1; continue
        try:
            blur_one(src, pct, a.out, tag, a.scale, a.quality)
        except Exception as e:
            print(f"failed: {src}: {e}", file=sys.stderr); rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
