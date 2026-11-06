#!/usr/bin/env python3
"""X のスペースの録音を m4a で保存する。ファイル名は「タイトル_ホスト名.m4a」。

使い方: python3 x_space_download.py "<スペースまたはそれを載せたポストのURL>" <出力ディレクトリ>
"""
import json, os, re, shutil, sys, tempfile

import yt_dlp
from yt_dlp.extractor.twitter import TwitterSpacesIE

# yt-dlp はスペースIDを13文字で切るが、14文字のIDがある。その分を通す（実行時だけ差し替え）
TwitterSpacesIE._VALID_URL = TwitterSpacesIE._VALID_URL.replace("{13}", "{13,14}")

LIMIT = 100 * 1024 * 1024  # GitHub の1ファイル上限


def safe(s):
    return re.sub(r'[/\\:*?"<>|]', "_", s).strip()


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    url, out_dir = sys.argv[1], sys.argv[2]
    try:
        with yt_dlp.YoutubeDL({"quiet": True, "skip_download": True}) as y:
            meta = y.extract_info(url, download=False)
    except Exception as e:
        hint = ("録音がまだ無い（配信中・終了直後）、録音が無効、または削除されている可能性。"
                "終了後に録音が公開されたら同じURLで再実行する。")
        sys.exit(f"取得できなかった: {e}\n{hint}\n※何も保存・push しない。ユーザーにこの旨を伝える。")
    title, host = meta.get("title") or meta["id"], meta.get("uploader") or ""
    name = safe(title)[:80] + (("_" + safe(host)) if host else "") + ".m4a"
    os.makedirs(out_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        with yt_dlp.YoutubeDL({"outtmpl": os.path.join(tmp, "space.%(ext)s")}) as y:
            y.download([url])
        src = next(os.path.join(tmp, f) for f in os.listdir(tmp) if f.startswith("space."))
        dst = os.path.join(out_dir, name)
        shutil.move(src, dst)
    size = os.path.getsize(dst)
    print(f"保存: {dst}  {size / 1024 / 1024:.1f}MB")
    if size > LIMIT:
        print("警告: 100MB 超。push せず、渡し方をユーザーに確認する。")


if __name__ == "__main__":
    main()
