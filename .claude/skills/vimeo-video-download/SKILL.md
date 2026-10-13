---
name: vimeo-video-download
description: Vimeo の動画を mp4 でダウンロードして Mac へ渡す。vimeo.com/<ID>/<ハッシュ> や player.vimeo.com の URL（?fl=pl&fe=vl&turnstile=… などの長い付きURLも）を渡されて「ダウンロード」「この動画を保存」「Vimeoを落として」などと言われたら必ずこれを使う。URLだけが貼られたときも用途を聞き返さず落とす。ファイル名は動画タイトル.mp4。
---

# Vimeo の動画を保存する

`vimeo.com/<ID>/<ハッシュ>` をそのまま `yt-dlp` に渡すと「The web client only works when logged-in」で失敗する。**`player.vimeo.com/video/<ID>?h=<ハッシュ>` に直して、`--referer https://vimeo.com/` を付ける**と、ログイン不要で落とせる。

## 手順

1. CLAUDE.md の手順どおり、先に `add_repo`（dik1-downloads, push）で接続し、clone 済みか確かめる。
2. 道具を入れる（無ければ）: `pip install -q yt-dlp`（ffmpeg は入っている）。
3. URL から ID とハッシュを取る。`vimeo.com/1063032362/351e195c19?…` なら ID=`1063032362`、ハッシュ=`351e195c19`（`?` 以降の turnstile などは捨てる）。
4. 形式を確かめる:
   ```
   yt-dlp -F --referer "https://vimeo.com/" "https://player.vimeo.com/video/<ID>?h=<ハッシュ>"
   ```
   「Failed to parse XML」の警告は無視してよい（HLS で取れる）。映像と音声が別々に出る。
5. scratchpad 内の空ディレクトリへ落とす（出力が大きいので `| tail -5` で絞る）:
   ```
   cd <空ディレクトリ> && yt-dlp --referer "https://vimeo.com/" -f "bv*+ba/b" --merge-output-format mp4 -o "%(title)s.%(ext)s" "https://player.vimeo.com/video/<ID>?h=<ハッシュ>" 2>&1 | tail -5
   ```
   - 1時間の動画で数分かかる。タイムアウトは10分にする。
6. 100MB 以下なら `/home/user/dik1-downloads/downloads/` へコピーする。**日本語ファイル名は文字コードの違いで `cp "<名前>"` が失敗することがあるので、`cp <ディレクトリ>/*.mp4` とワイルドカードで指定する。** CLAUDE.md どおり commit → `git pull --rebase origin main` → `git push origin HEAD:main`。100MB を超えたら push せず、渡し方をユーザーに確認する。
7. 返答には、保存したファイル名・長さ・サイズと「dik1-downloads の main へ push した（Mac のデスクトップへ自動で移る）」を書く。

## 注意

- stop hook が作業ブランチの未 push コミットを指摘する。dik1-downloads 側でも `git push -u origin <作業ブランチ>` を行う。
- 実績: 「あやか音声フルバージョン」（約1時間、最大360p）は約98.8MB で、ぎりぎり100MB 以内だった。長い動画は超えやすいので、結合後に必ずサイズを確かめる。
- 最高画質が低いのは、投稿者側が低画質で上げているため。
- 非公開・埋め込み制限の動画は失敗することがある。その旨を伝える。
- yt-dlp が古いと壊れることがある。失敗したら `pip install -U yt-dlp` を試す。
