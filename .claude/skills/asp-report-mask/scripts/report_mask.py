#!/usr/bin/env python3
"""ASPレポート（Highcharts）スクショの数値伏せ。

検出 → ぼかし/塗り潰し を自動で行う。
  1. グラフ領域全体をガウスぼかし（横軸ラベル 0-23 は残す）
  2. 集計表ヘッダーの3列目以降をセル単位でぼかし
  3. 金額末尾の「円」を単色グレーの矩形で塗り潰す

usage:
  python3 report_mask.py detect IMG              # 検出した座標だけ出す
  python3 report_mask.py mask   IMG [-o OUT] [--keep-cols N] [--no-yen]
"""
import argparse, os, sys
from PIL import Image, ImageFilter, ImageDraw

GREY = (210, 210, 210)      # 「円」を潰す色
INK = 150                   # これより暗ければ文字とみなす
DARK = 80                   # ヘッダー帯の黒
LIGHT = 140                 # ヘッダー内の区切り線


def detect(im):
    g = im.convert("L")
    p = g.load()
    W, H = g.size
    d = {}

    # --- 黒帯（上部バー / タブ / 「レポート全体」 / 集計表ヘッダー）を全部拾う
    x0, x1 = int(W * 0.10), int(W * 0.90)
    step = max(1, (x1 - x0) // 400)
    cols_n = len(range(x0, x1, step))

    def fill(y):
        return sum(1 for x in range(x0, x1, step) if p[x, y] < 150) / cols_n

    bands, run = [], None
    for y in range(H):
        if fill(y) > 0.6:
            run = y if run is None else run
        elif run is not None:
            bands.append([run, y - 1])
            run = None
    if run is not None:
        bands.append([run, H - 1])
    merged = []
    for b in bands:                                  # 文字行で途切れるので近いものを繋ぐ
        if merged and b[0] - merged[-1][1] <= 10:
            merged[-1][1] = b[1]
        else:
            merged.append(b)
    merged = [b for b in merged if b[1] - b[0] >= 15]
    if len(merged) < 2:
        sys.exit("黒帯が見つからない（レポート画面ではない？）")
    d["hdr_top"], d["hdr_bot"] = merged[-1]          # 集計表ヘッダー
    title_bot = merged[-2][1]                        # 「レポート全体：昨日」の帯

    # --- コンテンツ枠: タイトル帯の下の白い隙間で、左右のボーダー線を拾う
    probe = title_bot + int(H * 0.04)
    xs = [x for x in range(W) if p[x, probe] < 245]
    l = [x for x in xs if x < W * 0.25] or [0]        # 外枠が二重の場合は内側を採る
    r = [x for x in xs if x > W * 0.75] or [W - 1]
    d["left"], d["right"] = max(l) + 2, min(r) - 1

    # --- ヘッダー内の列区切り（明るい縦線）
    ys = range(d["hdr_top"] + 2, d["hdr_top"] + 12)
    light = [sum(p[x, y] for y in ys) / len(ys) > LIGHT for x in range(W)]
    edges, cols, run = [], [], None
    for x in range(d["left"], d["right"]):
        if light[x] and run is None:
            run = x
        elif not light[x] and run is not None:
            edges.append((run, x))
            run = None
    if run is not None:
        edges.append((run, d["right"]))
    for a, b in zip(edges, edges[1:]):
        cols.append((a[1], b[0]))
    d["cols"] = cols

    # --- 数値行（ヘッダー直下の最初の文字行）
    y = d["hdr_bot"] + 1
    while y < H and not any(p[x, y] < INK for x in range(d["left"], d["right"])):
        y += 1
    vt = y
    while y < H and any(p[x, y] < INK for x in range(d["left"], d["right"])):
        y += 1
    d["val_top"], d["val_bot"] = vt, y - 1

    # --- グラフ上端: 凡例行の少し上
    y = title_bot + 1
    while y < d["hdr_top"] and not any(p[x, y] < 240
                                       for x in range(d["left"] + 4, d["right"] - 4)):
        y += 1
    d["chart_top"] = max(title_bot + 1, y - int(W * 0.016))

    # --- グラフ下端: 横軸ライン（幅の7割以上が非白の一番下の行）。表の枠線は除く
    limit = d["hdr_top"] - int(H * 0.05)
    axis = None
    for y in range(d["chart_top"], limit):
        n = sum(1 for x in range(d["left"], d["right"], 2) if p[x, y] < 230)
        if n / len(range(d["left"], d["right"], 2)) > 0.7:
            axis = y
    if axis is None:
        sys.exit("グラフ下端（横軸ライン）が見つからない")
    d["chart_bot"] = axis + int(W * 0.008)
    return d


def yen_boxes(im, d, cols):
    """各列の一番右の文字塊（＝「円」）の座標を返す"""
    p = im.convert("L").load()
    ys = range(d["val_top"], d["val_bot"] + 1)
    out = []
    for a, b in cols:
        ink = lambda x: any(p[x, y] < INK for y in ys)
        x = b - 1
        while x > a and not ink(x):
            x -= 1
        right = x
        while x > a and (ink(x) or ink(x - 1)):
            x -= 1
        left = x + 1
        gy = [y for y in ys if any(p[xx, y] < INK for xx in range(left, right + 1))]
        if not gy:
            continue
        w, h = right - left + 1, gy[-1] - gy[0] + 1
        if not 0.6 <= w / h <= 1.5:
            print(f"  ! 列({a},{b}) の右端が「円」らしくない w={w} h={h} → 要目視", file=sys.stderr)
        out.append((left, gy[0], right, gy[-1]))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["detect", "mask"])
    ap.add_argument("img")
    ap.add_argument("-o", "--out")
    ap.add_argument("--keep-cols", type=int, default=2,
                    help="ぼかさずに残すヘッダー列数（既定2＝空欄とクリック数）")
    ap.add_argument("--no-yen", action="store_true", help="「円」の塗り潰しをしない")
    a = ap.parse_args()

    im = Image.open(a.img).convert("RGB")
    d = detect(im)
    W = im.width
    if a.cmd == "detect":
        for k in ("left", "right", "chart_top", "chart_bot", "hdr_top", "hdr_bot",
                  "val_top", "val_bot"):
            print(f"{k:10} {d[k]}")
        print("cols      ", d["cols"])
        return

    blur = lambda box, r: im.paste(im.crop(box).filter(ImageFilter.GaussianBlur(r)), box)

    blur((d["left"], d["chart_top"], d["right"], d["chart_bot"]), round(W / 87))

    targets = d["cols"][a.keep_cols:]
    for x0, x1 in targets:
        blur((x0, d["hdr_top"] - 6, x1, d["hdr_bot"] + 6), round(W / 78))

    if not a.no_yen:
        dr = ImageDraw.Draw(im)
        for l, t, r, b in yen_boxes(im, d, targets):
            dr.rectangle([l - 4, t - 5, r + 4, b + 5], fill=GREY)

    out = a.out or os.path.expanduser(
        "~/Desktop/" + os.path.splitext(os.path.basename(a.img))[0] + "_masked.png")
    im.save(out)
    print(out)


if __name__ == "__main__":
    main()
