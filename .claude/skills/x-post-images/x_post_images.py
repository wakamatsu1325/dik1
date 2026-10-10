#!/usr/bin/env python3
"""X の投稿に付いている画像を原寸で保存する。
使い方: x_post_images.py <投稿URL> <出力ディレクトリ>
出力: <出力ディレクトリ>/<いいね数>_<本文1行目>/<いいね数>_<本文1行目>_N.拡張子
最後に、本文にあるリンク(展開済み)を「本文リンク: URL」で出す。転送先は踏まない。
"""
import re, sys, json, urllib.request
from pathlib import Path

url, out = sys.argv[1], Path(sys.argv[2])
m = re.search(r"(?:x|twitter)\.com/([^/]+)/status/(\d+)", url)
if not m:
    sys.exit("投稿URLではない")
user, tid = m.groups()
def get(u):  # 既定のUser-Agentは弾かれる(403)
    return urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": "curl/8"}))
t = json.load(get(f"https://api.fxtwitter.com/{user}/status/{tid}"))["tweet"]
photos = (t.get("media") or {}).get("photos") or []
if not photos:
    sys.exit("画像がない投稿")
body = t["text"]
first = next((l for l in re.sub(r"https?://\S+", "", body).splitlines() if l.strip()), "")
first = re.sub(r'[/\\:*?"<>|]', "", first).strip()
base = f"{t['likes']}_{first}"[:120] if first else f"{t['likes']}_{t['author']['name']}_{tid}"
d = out / base
d.mkdir(parents=True, exist_ok=True)
for i, p in enumerate(photos, 1):
    u = re.sub(r"\?.*", "", p["url"]) + "?name=orig"
    ext = re.search(r"\.(jpg|jpeg|png|webp)", p["url"]).group(1)
    f = d / f"{base}_{i}.{ext}"
    f.write_bytes(get(u).read())
    print(f, f"{f.stat().st_size/1e6:.1f}MB")
for l in dict.fromkeys(re.findall(r"https?://[^\s】」）)]+", body)):
    print("本文リンク:", l)
