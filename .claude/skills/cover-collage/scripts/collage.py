#!/usr/bin/env python3
"""メイン画像1枚 + サブ画像2枚を3分割レイアウトの正方形1枚に合成する。

レイアウト（既定 1408x1408）:
  ┌───────────────┐
  │     メイン     │  高さ = size * main_ratio
  ├───────┬───────┤
  │ サブ1  │ サブ2  │  残りを左右で半分ずつ
  └───────┴───────┘
隙間・枠線なし。各枠へは「枠を埋めるように拡大して切り抜く」（cover）。

切り抜き位置は --main/--sub1/--sub2 に "FX FY ZOOM" で指定する。
  FX, FY : 元画像上で枠の中心に置きたい点（0〜1 の比率）。既定 0.5 0.5
  ZOOM   : 1 = 枠を埋める最小の拡大。1.3 なら 1.3 倍寄る。既定 1
中心点が端に寄りすぎた場合は、画像外にはみ出さないよう自動で内側へ戻す。

出力には「3分割画像」の印 `DogURL:split3` を書き込む（JPEGはコメント、PNGはテキスト）。
Dog URL の集計表「1枚目3分割」がこれを読む。印は見た目に出ない。
JPEG・PNG以外で書き出すと印は付かない（警告を出す）。
"""
import argparse
import os
import sys

from PIL import Image
from PIL.PngImagePlugin import PngInfo

MARK = 'DogURL:split3'


def parse_focus(s):
    v = [float(x) for x in s.split()]
    if len(v) == 2:
        v.append(1.0)
    if len(v) != 3:
        raise argparse.ArgumentTypeError('"FX FY [ZOOM]" の形で指定')
    return v


def cover(im, w, h, fx, fy, zoom):
    iw, ih = im.size
    scale = max(w / iw, h / ih) * zoom
    cw, ch = w / scale, h / scale  # 元画像上の切り抜きサイズ
    x0 = min(max(fx * iw - cw / 2, 0), iw - cw)
    y0 = min(max(fy * ih - ch / 2, 0), ih - ch)
    return im.resize((w, h), Image.LANCZOS, box=(x0, y0, x0 + cw, y0 + ch))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('main_img')
    p.add_argument('sub1_img')
    p.add_argument('sub2_img')
    p.add_argument('--out', default='collage.jpg')
    p.add_argument('--size', type=int, default=1408)
    p.add_argument('--main-ratio', type=float, default=0.60)
    for k in ('main', 'sub1', 'sub2'):
        p.add_argument(f'--{k}', type=parse_focus, default=[0.5, 0.5, 1.0])
    a = p.parse_args()

    S = a.size
    mh = round(S * a.main_ratio)
    sh = S - mh
    lw = S // 2
    rw = S - lw

    canvas = Image.new('RGB', (S, S))
    canvas.paste(cover(Image.open(a.main_img).convert('RGB'), S, mh, *a.main), (0, 0))
    canvas.paste(cover(Image.open(a.sub1_img).convert('RGB'), lw, sh, *a.sub1), (0, mh))
    canvas.paste(cover(Image.open(a.sub2_img).convert('RGB'), rw, sh, *a.sub2), (lw, mh))
    ext = os.path.splitext(a.out)[1].lower()
    if ext in ('.jpg', '.jpeg'):
        canvas.save(a.out, quality=95, comment=MARK.encode())
    elif ext == '.png':
        info = PngInfo()
        key, value = MARK.split(':')
        info.add_text(key, value)
        canvas.save(a.out, pnginfo=info)
    else:
        canvas.save(a.out, quality=95)
        print(f'警告: {ext} には3分割の印を書けません。集計表では手入力が要ります', file=sys.stderr)
    print(f'saved {a.out}  main {S}x{mh} / sub1 {lw}x{sh} / sub2 {rw}x{sh}')


if __name__ == '__main__':
    main()
