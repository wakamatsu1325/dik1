#!/usr/bin/env python3
"""X の投稿の動画を最高画質で保存する。ファイル名は「ユーザー名_投稿本文.mp4」。
使い方: x_video_download.py <投稿URL> <出力ディレクトリ>
"""
import re, sys, json, urllib.request
from pathlib import Path

LIMIT = 95_000_000
url, out = sys.argv[1], Path(sys.argv[2])
m = re.search(r"(?:x|twitter)\.com/([^/]+)/status/(\d+)", url)
if not m:
    sys.exit("投稿URLではない")
user, tid = m.groups()
def get(u):  # 既定のUser-Agentは弾かれる(403)
    return urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": "curl/8"}))
data = json.load(get(f"https://api.fxtwitter.com/{user}/status/{tid}"))["tweet"]
videos = [x for x in data["media"]["all"] if x["type"] in ("video", "gif")]
if not videos:
    sys.exit("動画がない投稿")
text = re.sub(r"\s*https?://\S+", "", data["text"])           # t.co 等のURLを除く
text = re.sub(r"[\r\n]+", "", text)                            # 改行は詰める
text = re.sub(r'[/\\:*?"<>|]', "", text).strip()               # ファイル名に使えない文字
name = re.sub(r'[/\\:*?"<>|\r\n]', "", data["author"]["name"]).strip() or user   # 表示名(例: 凡人くん)。@IDではない
base = f"{name}_{text}"[:120] or f"{user}_{tid}"
while len(base.encode()) > 230:   # ファイル名は255バイトまで(日本語は1文字3バイト)。末尾の _1.mp4 の分を空ける
    base = base[:-1]
out.mkdir(parents=True, exist_ok=True)
for i, v in enumerate(videos):
    mp4 = [f for f in v.get("formats", []) if f.get("container") == "mp4"]
    # 100MB以下(GitHubの上限)に収まる最高ビットレートを選ぶ。全部超えるなら最低ビットレートで、超過を警告する
    best = v["url"]
    for f in sorted(mp4, key=lambda f: -f.get("bitrate", 0)):
        best = f["url"]
        size = int(get(best).headers.get("Content-Length", 0))
        if size <= LIMIT:
            break
    else:
        print("警告: どの画質も100MBを超える", file=sys.stderr)
    name = base + (f"_{i+1}" if len(videos) > 1 else "") + ".mp4"
    path = out / name
    path.write_bytes(get(best).read())
    print(path, f"{path.stat().st_size/1e6:.1f}MB", f"{v.get('duration', 0):.0f}秒")
