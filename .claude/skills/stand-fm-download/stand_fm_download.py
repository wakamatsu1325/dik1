#!/usr/bin/env python3
"""stand.fm のエピソード音声(m4a)を保存する。使い方: stand_fm_download.py <エピソードURL> <出力ディレクトリ>"""
import html, json, re, subprocess, sys
from pathlib import Path

url, outdir = sys.argv[1], Path(sys.argv[2])
m = re.search(r"episodes/([0-9a-f]{24})", url)
if not m:
    sys.exit("エピソードURL(stand.fm/episodes/<24桁ID>)ではない")
eid = m.group(1)
page = subprocess.run(["curl", "-sL", f"https://stand.fm/episodes/{eid}"], capture_output=True, text=True, check=True).stdout

# このエピソード自身の音声: episodeId が一致する topic の downloadUrl（ページ内には他エピソードの音声も混ざる）
audio = None
for t in re.finditer(r'\{"id":"[0-9a-f]{24}","episodeId":"%s".{0,200}?"downloadUrl":"([^"]+)"' % eid, page):
    audio = t.group(1)
    break
if not audio:
    sys.exit("音声URLが見つからない（非公開・有料・削除済みの可能性）")

title = re.search(r'og:title" content="([^"]*)"', page)
title = html.unescape(title.group(1)) if title else eid
title = re.sub(r"\s*\|\s*stand\.fm\s*$", "", title)
# 「エピソード名 - チャンネル名」→「エピソード名_チャンネル名」（チャンネル名の飾りは落とす）
ep, _, ch = title.rpartition(" - ")
if ep:
    ch = re.sub(r"[❤︎♡♥]*\s*stand\.fm公式パートナー$", "", ch).strip()
    title = f"{ep}_{ch}"
name = re.sub(r'[\\/:*?"<>|]', "_", title).strip() + ".m4a"

outdir.mkdir(parents=True, exist_ok=True)
dest = outdir / name
subprocess.run(["curl", "-sL", "-f", audio, "-o", str(dest)], check=True)
print(json.dumps({"file": str(dest), "bytes": dest.stat().st_size}, ensure_ascii=False))
