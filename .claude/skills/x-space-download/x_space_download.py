#!/usr/bin/env python3
"""X のスペースの録音を m4a で保存する。ファイル名は「タイトル_ホスト名.m4a」。

使い方: python3 x_space_download.py "<スペースまたはそれを載せたポストのURL>" <出力ディレクトリ>
"""
import json, os, re, shutil, subprocess, sys, tempfile

LIMIT = 100 * 1024 * 1024  # GitHub の1ファイル上限


def safe(s):
    return re.sub(r'[/\\:*?"<>|]', "_", s).strip()


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    url, out_dir = sys.argv[1], sys.argv[2]
    if not shutil.which("yt-dlp"):
        subprocess.run([sys.executable, "-m", "pip", "install", "-q", "yt-dlp"], check=True)
    meta = json.loads(subprocess.run(["yt-dlp", "-J", "--no-download", url],
                                     check=True, capture_output=True, text=True).stdout)
    title, host = meta.get("title") or meta["id"], meta.get("uploader") or ""
    name = safe(title)[:80] + (("_" + safe(host)) if host else "") + ".m4a"
    os.makedirs(out_dir, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["yt-dlp", "-o", os.path.join(tmp, "space.%(ext)s"), url], check=True)
        src = next(os.path.join(tmp, f) for f in os.listdir(tmp) if f.startswith("space."))
        dst = os.path.join(out_dir, name)
        shutil.move(src, dst)
    size = os.path.getsize(dst)
    print(f"保存: {dst}  {size / 1024 / 1024:.1f}MB")
    if size > LIMIT:
        print("警告: 100MB 超。push せず、渡し方をユーザーに確認する。")


if __name__ == "__main__":
    main()
