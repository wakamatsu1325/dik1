#!/usr/bin/env python3
"""原本と「モザイク済み出力」から、ブロックサイズと対応矩形を同定する。"""
import sys
from PIL import Image, ImageChops, ImageStat, ImageFilter

def sc(a,b): return sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/3
def grad(im):
    g=im.convert("L"); w,h=g.size; px=g.load(); s=0;n=0
    for y in range(h-1):
        for x in range(w-1): s+=abs(px[x,y]-px[x+1,y])+abs(px[x,y]-px[x,y+1]); n+=2
    return s/n
def block(im,k):
    w,h=im.size
    return im.resize((max(1,w//k),max(1,h//k)),Image.BOX).resize((w,h),Image.NEAREST)

def align(orig,samp):
    W,H=samp.size; ar=W/H
    sref=samp.filter(ImageFilter.GaussianBlur(3))
    best=None
    for w in range(int(orig.width*0.6), orig.width+1, max(4,orig.width//40)):
        h=round(w/ar)
        if h>orig.height: continue
        for x0 in range(0, orig.width-w+1, max(4,(orig.width-w)//8 or 10**9)):
            for y0 in range(0, orig.height-h+1, max(4,(orig.height-h)//8 or 10**9)):
                c=orig.crop((x0,y0,x0+w,y0+h)).resize((W,H),Image.LANCZOS)
                v=sc(c.filter(ImageFilter.GaussianBlur(3)),sref)
                if best is None or v<best[0]: best=(v,x0,y0,w,h)
    return best

def refine(orig,samp,x0,y0,w,ks=(3,4,5,6)):
    """粗探索の結果を、モザイク当てはめの残差で細かく詰める。"""
    W,H=samp.size; ar=W/H
    best=None
    for step,span in ((8,40),(3,12),(1,4)):
        cx,cy,cw = (x0,y0,w) if best is None else best[1:]
        for dw in range(-span,span+1,step):
            ww=cw+dw; hh=round(ww/ar)
            if ww<32 or ww>orig.width or hh>orig.height: continue
            for dx in range(-span,span+1,step):
                xx=cx+dx
                if xx<0 or xx+ww>orig.width: continue
                for dy in range(-span,span+1,step):
                    yy=cy+dy
                    if yy<0 or yy+hh>orig.height: continue
                    b=orig.crop((xx,yy,xx+ww,yy+hh)).resize((W,H),Image.LANCZOS)
                    v=min(sc(block(b,k),samp) for k in ks)
                    if best is None or v<best[0]: best=(v,xx,yy,ww)
    return best

def main(op,sp):
    orig=Image.open(op).convert("RGB"); samp=Image.open(sp).convert("RGB")
    W,H=samp.size
    _,x0,y0,w,h=align(orig,samp)
    _,x0,y0,w=refine(orig,samp,x0,y0,w)
    h=round(w*H/W)
    base=orig.crop((x0,y0,x0+w,y0+h)).resize((W,H),Image.LANCZOS)
    tg=grad(samp)
    rows=[]
    for k in range(2,13):
        r=block(base,k); rows.append((abs(grad(r)-tg),k,grad(r),sc(r,samp)))
    rows.sort()
    k=rows[0][1]
    print(f"{sp}")
    print(f"  原本 {orig.size}  出力 {W}x{H}  対応矩形 ({x0},{y0}) {w}x{h}  縮小率 {orig.width/W:.2f}")
    print(f"  正解の勾配 {tg:.3f}")
    for d,kk,g,r in rows[:4]:
        print(f"    k={kk}  勾配 {g:.3f} (差 {d:.3f})  残差 {r:.3f}")
    print(f"  => ブロック {k}px（出力上） / 原寸換算 {orig.width/(W/k):.1f}px / 横幅比 {100*k/W:.2f}%")
    return k

if __name__=="__main__":
    main(sys.argv[1],sys.argv[2])
