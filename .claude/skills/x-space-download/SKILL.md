---
name: x-space-download
description: X（旧Twitter）のスペース（Spaces）の録音を音声ファイル（m4a）でダウンロードして Mac へ渡す。x.com/…/status/… や x.com/i/spaces/… のURLを渡されて「このスペースをダウンロードして」「スペースを保存」「スペースを落として」「スペースの録音」などと言われたら必ずこれを使う。ファイル名の末尾にホストのユーザー名を付ける。
---

# X のスペースを音声で保存する

yt-dlp が全部やる。ログイン・APIキー不要。録音が公開されているスペースだけが対象（終了後に録音が無効、または削除されていると取れない）。

## 手順

1. yt-dlp が無ければ `pip install -q yt-dlp`（ffmpeg は入っている）。
2. 先に CLAUDE.md の手順どおり `add_repo`（dik1-downloads, push）で接続し、clone 済みか確かめる。
3. 作業用の空ディレクトリ（scratchpad 内）へ落とす。ホスト名（`uploader`）を出力名の末尾に付ける:
   ```
   yt-dlp -o "%(title).80B_%(uploader)s.%(ext)s" "<URL>"
   ```
   - 例: `とりあえず聞け！集団戦のためになる話_MAD@大学教授が教える口説きの論理.m4a`
   - 「ユーザー名」は X の表示名（`uploader`）。`@ID`（`uploader_id`）ではない。
   - 事前に `yt-dlp -F "<URL>"` で `audio only` の形式があるか見ると、録音の有無が分かる。
   - 2時間級で 8〜10分かかる。タイムアウトは 10分（600000ms）にする。
4. 100MB 以下なら `/home/user/dik1-downloads/downloads/` へコピーし、CLAUDE.md どおり commit → `git pull --rebase origin main` → `git push origin HEAD:main`。
   - 100MB を超えたら push せず、渡し方をユーザーに確認する。
5. 返答には、保存したファイル名・長さ・サイズと「dik1-downloads の main へ push した（Mac のデスクトップへ自動で移る）」を書く。出力は音声1ファイルだけ（映像は無い）。

## 注意

- 作業ブランチ（claude/…）の未 push コミットが stop hook に指摘される。`git push -u origin <作業ブランチ>` も行う。
