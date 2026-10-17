---
name: 8tsu-video-download
description: 8tsu.net（9tsu / 動画8tsu）の動画ページの動画を、最高画質の mp4 でダウンロードして Mac へ渡す。8tsu.net/…/数字 のURLを渡されて「最高画質でDL」「この動画を保存」「8tsuを落として」などと言われたら必ずこれを使う。URLだけが貼られたときも用途を聞き返さず落とす。100MB を超える動画は再エンコードせず分割して送る。
---

# 8tsu.net の動画を保存する

8tsu.net のページは動画そのものを持たず、外部プレーヤー（実績は `ok.ru/videoembed/<ID>`）を iframe で埋め込んでいる。**埋め込み先を特定して、そこから最高画質の mp4 を落とす。**

## 手順

1. CLAUDE.md の手順どおり、先に `add_repo`（dik1-downloads, push）で接続し、clone 済みか確かめる。
2. ページを取得し、埋め込みを探す（UA は Mozilla を付ける）:
   ```
   curl -sL -A "Mozilla/5.0" -o page.html <URL>
   grep -oE 'iframe[^>]*src="[^"]*"|videoembed/[0-9]+' page.html | sort -u
   ```
   - 複数の iframe（パート分け）があれば全部落とす。ファイル名の末尾に連番を付ける。
   - 題名は `og:title`（例: `MUSIC FAIR 動画　2026年10月17日`）。ファイル名は「動画」を除いて整える（例: `MUSIC FAIR 2026年10月17日.mp4`）。
3. ok.ru の場合、`yt-dlp` は `the JSON object must be str, bytes or bytearray, not dict` で失敗する（2026-08 版で確認）。**埋め込みページの `data-options` を自分で読む**:
   ```
   curl -sL -A "Mozilla/5.0" -e https://8tsu.net/ https://ok.ru/videoembed/<ID> -o ok.html
   ```
   `data-options` を html.unescape → JSON。`flashvars.metadata`（文字列ならもう一度 JSON）の `videos` に `mobile/lowest/low/sd/hd` が並ぶ。**一番上の画質（普通は `hd` = 720p）の url を選ぶ。** ほかに `hlsManifestUrl` もある。
   - Python は `python3 -I` で動かす。
   - url は期限付き。取ったらすぐ落とす。
4. scratchpad 内の空ディレクトリへ落とす（30分で約340MB。タイムアウトは10分）:
   ```
   curl -sL -m 900 -A "Mozilla/5.0" -e https://ok.ru/ -o "<名前>.mp4" "<hdのurl>"
   ffprobe -v error -show_entries stream=codec_name,width,height -show_entries format=duration -of compact "<名前>.mp4"
   ```
5. サイズを見る。**100MB（GitHub の上限）を超える場合は、ユーザーが「分割」を選ぶ前提で再エンコードせず分割する**（初回は聞いた上で「分割して送る」が選ばれた）。1本が約75MB以下になるよう、30分・約340MB なら 370 秒ごとの5本:
   ```
   ffmpeg -v error -i "<名前>.mp4" -c copy -f segment -segment_time 370 -reset_timestamps 1 -segment_start_number 1 part_%d.mp4
   ```
   - 4分割（460秒）だと1本が約107MBになり上限超え。**必ず分割後に全ファイルのサイズを確かめる。**
   - `part_N.mp4` を `<名前>_N.mp4` に改名。結合前の元ファイルは送らない。
6. `/home/user/dik1-downloads/downloads/` へ `cp <ディレクトリ>/*_[0-9].mp4` とワイルドカードで指定してコピー（日本語名の文字コード対策）。commit → `git pull --rebase origin main` → `git push origin HEAD:main`。
7. stop hook 対策に、dik1-downloads 側でも `git push -u origin <作業ブランチ>` を行う。
8. 返答には、保存したファイル名・画質・長さ・サイズと「dik1-downloads の main へ push した（Mac のデスクトップへ自動で移る）」を書く。分割したときは、Mac で `ffmpeg -f concat` により無劣化で結合できることも添える。

## 注意

- 埋め込み先が ok.ru 以外（dailymotion など）なら、まず `yt-dlp -F` を試す。
- 見つかる画質が低いのは、掲載元が低画質で上げているため。
- push 時の「50MB 超」の警告は無視してよい（100MB 未満なら通る）。
