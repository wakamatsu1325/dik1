---
name: utage-video-download
description: UTAGE（utage-system.com）のページに埋め込まれた動画を mp4 でダウンロードして Mac へ渡す。utage-system.com/p/…（?rid=… 付きも）の URL を渡されて「ダウンロード」「この動画を保存」「UTAGEを落として」などと言われたら必ずこれを使う。URLだけが貼られたときは用途を聞き返さず落とす。100MB を超えるときは再エンコードせず分割して送る。
---

# UTAGE の動画を保存する

ページ HTML の中の JSON に、動画の HLS（m3u8）の URL が入っている。ログイン不要で、`ffmpeg` にそのまま渡せば落とせる。

## 手順

1. CLAUDE.md の手順どおり、先に `add_repo`（dik1-downloads, push）で接続し、clone 済みか確かめる。
2. ページを取り、動画のタイトルと m3u8 を抜く（`type":"video"` の要素。`title` と `src`）:
   ```
   curl -sL "<URL>" | python3 -I -c "import sys,re,html;t=sys.stdin.read();print(re.findall(r'\"title\":\"([^\"]+)\"',t)[:3]);print(set(re.findall(r'https:[^\"]+?video\.m3u8',t.replace('\\\\/','/'))))"
   ```
   JSON は `\/` でエスケープされ、日本語は `\uXXXX` なので、必要ならデコードする。動画が複数あれば全部落とす（ファイル名の末尾に `_1` `_2`）。
3. scratchpad に落とす（再エンコードしない）:
   ```
   ffmpeg -loglevel error -y -i "<m3u8>" -c copy -bsf:a aac_adtstoasc "<タイトル>.mp4"
   ```
   35分で約114MB。タイムアウトは10分。`ffprobe` で長さを確かめる。
4. 100MB 以下ならそのまま、超えたら再エンコードせず分割する（約半分ずつ、画質は落ちない）:
   ```
   ffmpeg -loglevel error -y -i "<タイトル>.mp4" -c copy -f segment -segment_time <秒> -reset_timestamps 1 "out/<タイトル>_part%d.mp4"
   ```
   各ファイルが100MB 以下になるよう `segment_time` を決める（全長÷2 弱）。
5. `cp out/*.mp4 /home/user/dik1-downloads/downloads/`（日本語名はワイルドカードで）→ commit → push。
6. 返答には、ファイル名・長さ・サイズと「dik1-downloads の main へ push した（Mac のデスクトップへ自動で移る）」を書く。

## 注意

- **Mac が同時に `main` を更新する（移動済みコミット）ので、push は `cannot lock ref` で拒否されることがある。** `git pull --rebase origin main && git push origin HEAD:main` を数回繰り返す。
- stop hook が未 push を指摘するので、作業ブランチも `git push -u origin HEAD` しておく。
- 実績: 「MAD構1本目ローンチ_1」は35分38秒で約114MB → 2分割（約60MB と約57MB）で送った。
- 動画が埋め込みでなく外部（YouTube・Vimeo）のときは、それぞれのスキルへ回す。
