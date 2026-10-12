---
name: tiktok-video-download
description: TikTok の動画を mp4 でダウンロードして Mac へ渡す。tiktok.com/@…/video/… のURL（vt.tiktok.com などの短縮URLも）を渡されて「ダウンロード」「この動画を保存」「TikTokを落として」などと言われたら必ずこれを使う。URLだけが貼られたときも用途を聞き返さず落とす。ファイル名は「投稿者ID_動画ID.mp4」。
---

# TikTok の動画を保存する

ログイン不要。`yt-dlp` に **`--impersonate chrome`** を付けて落とす。付けないと「Unexpected response from webpage request」で失敗する（`curl_cffi` が必要）。

## 手順

1. CLAUDE.md の手順どおり、先に `add_repo`（dik1-downloads, push）で接続し、clone 済みか確かめる。
2. 道具を入れる（無ければ）:
   ```
   pip install -q yt-dlp curl_cffi
   ```
3. scratchpad 内の空ディレクトリへ落とす:
   ```
   cd <空ディレクトリ> && yt-dlp --impersonate chrome -f "best[ext=mp4]/best" -o "%(uploader)s_%(id)s.%(ext)s" "<URL>"
   ```
   - ウォーターマーク無しの最高画質が選ばれる（例: 1080p）。
4. 100MB 以下なら `/home/user/dik1-downloads/downloads/` へコピーし、CLAUDE.md どおり commit → `git pull --rebase origin main` → `git push origin HEAD:main`。100MB を超えたら push せず、渡し方をユーザーに確認する。
5. 返答には、保存したファイル名・サイズと「dik1-downloads の main へ push した（Mac のデスクトップへ自動で移る）」を書く。

## 注意

- stop hook が作業ブランチの未 push コミットを指摘する。dik1-downloads 側でも `git push -u origin <作業ブランチ>` を行う。
- 投稿が削除済み・非公開だと失敗する。その旨を伝える。
- yt-dlp が古いと壊れることがある。失敗したら `pip install -U yt-dlp` を試す。
