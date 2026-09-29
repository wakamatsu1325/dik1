#!/usr/bin/env python3
"""原本と「見本のぼかし画像」の組から、ぼかしの種類と強度を同定する。

見本が原本の一部を切り抜いて縮小したもの（スクショ等）でも、対応位置を自動で探す。

  python3 fit_blur.py 原本.jpg 見本.png

出力: 最適 sigma（見本上 / 原寸換算 / 横幅比%）、モデル比較、タイル別sigma。
横幅比% を blur.py --sigma-pct に渡せば再現できる。
"""
import argparse, sys
from PIL import Image, ImageChops, ImageStat, ImageFilter


def sc(a, b):
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3


def coarse(orig, small, K=8):
    W0, H0 = orig.size; w, h = small.size; ar = w / h
    base = orig.resize((W0 // K, H0 // K), Image.BICUBIC)
    BW, BH = base.size
    tgt = small.resize((48, 36), Image.BICUBIC).filter(ImageFilter.GaussianBlur(1))
    best = None
    for W in range(int(BW * 0.30), BW + 1, 2):
        H = int(round(W / ar))
        if H > BH: continue
        for x in range(0, BW - W + 1, 2):
            for y in range(0, BH - H + 1, 2):
                c = base.crop((x, y, x + W, y + H)).resize((48, 36), Image.BICUBIC) \
                        .filter(ImageFilter.GaussianBlur(1))
                v = sc(c, tgt)
                if best is None or v < best[0]: best = (v, x * K, y * K, W * K, H * K)
    return best


def refine(orig, small, g, step, rad, sig, free_aspect=False):
    W0, H0 = orig.size; w, h = small.size; ar = w / h
    _, x0, y0, W, H = g
    tgt = small.filter(ImageFilter.GaussianBlur(1.5))
    best = None
    Hs = range(H - rad, H + rad + 1, step) if free_aspect else [None]
    for W2 in range(W - rad, W + rad + 1, step):
        for H2 in (Hs if free_aspect else [int(round(W2 / ar))]):
            for x in range(x0 - rad, x0 + rad + 1, step):
                for y in range(y0 - rad, y0 + rad + 1, step):
                    if x < 0 or y < 0 or x + W2 > W0 or y + H2 > H0: continue
                    c = orig.crop((x, y, x + W2, y + H2)).resize((w, h), Image.LANCZOS) \
                            .filter(ImageFilter.GaussianBlur(sig))
                    v = sc(c, tgt)
                    if best is None or v < best[0]: best = (v, x, y, W2, H2)
    return best


def main():
    p = argparse.ArgumentParser(description="ぼかしの種類と強度を同定する")
    p.add_argument("original"); p.add_argument("sample")
    p.add_argument("--seed", nargs=4, type=int, metavar=("X", "Y", "W", "H"),
                   help="粗探索を飛ばして対応矩形を直接指定")
    a = p.parse_args()

    o = Image.open(a.original).convert("RGB"); s = Image.open(a.sample).convert("RGB")
    W0 = o.size[0]; w, h = s.size
    g = (0, *a.seed) if a.seed else coarse(o, s)
    g = refine(o, s, g, 4, 20, 2.5)
    g = refine(o, s, g, 1, 4, 2.5, free_aspect=True)
    _, x, y, W, H = g
    print(f"原本 {o.size}  見本 {s.size}")
    print(f"対応矩形 ({x},{y}) {W}x{H}  縮小率 X {W/w:.4f} / Y {H/h:.4f}")

    R = o.crop((x, y, x + W, y + H)).resize((w, h), Image.LANCZOS)
    k = W / w
    cands = [(sc(R.filter(ImageFilter.GaussianBlur(i / 20)), s), "gauss", i / 20)
             for i in range(2, 160)]
    cands += [(sc(R.filter(ImageFilter.BoxBlur(i / 20)), s), "box", i / 20)
              for i in range(4, 200, 2)]
    cands += [(sc(R.resize((max(1, w // n), max(1, h // n)), Image.BOX)
                   .resize((w, h), Image.NEAREST), s), "pixel", n) for n in range(2, 25)]
    cands.sort()
    print("モデル比較（残差の小さい順）:")
    for v, m, prm in cands[:5]:
        print(f"   {m:6s} {prm:<6} 残差 {v:.3f}")

    sg = min(c for c in cands if c[1] == "gauss")[2]
    pct = 100 * sg * k / W0
    print(f"\n最適 gauss sigma: 見本上 {sg}px / 原寸換算 {sg*k:.2f}px / "
          f"横幅比 {pct:.3f}%  -> blur.py --sigma-pct {pct:.3f}")
    for name, ref in (("P1", 0.600), ("P2", 0.230)):
        e = sc(R.filter(ImageFilter.GaussianBlur(ref / 100 * W0 / k)), s)
        print(f"   {name} ({ref}%) を当てた場合の残差 {e:.3f}")

    print("タイル別 sigma（全面均一かの確認）:")
    for ty in range(3):
        row = []
        for tx in range(3):
            bx = (tx * w // 3, ty * h // 3, (tx + 1) * w // 3, (ty + 1) * h // 3)
            t = s.crop(bx)
            row.append(min((sc(R.filter(ImageFilter.GaussianBlur(i / 20)).crop(bx), t), i / 20)
                           for i in range(2, 160))[1])
        print("   ", row)
    m1, m2 = ImageStat.Stat(R.filter(ImageFilter.GaussianBlur(sg))), ImageStat.Stat(s)
    print("平均 再現", [round(v, 1) for v in m1.mean], " 見本", [round(v, 1) for v in m2.mean])
    return 0


if __name__ == "__main__":
    sys.exit(main())
