---
name: x-space-download
description: X（旧Twitter）のスペース（Spaces）の録音を音声ファイル（m4a）でダウンロードして Mac へ渡す。x.com/…/status/… や x.com/i/spaces/… のURLを渡されて「このスペースをダウンロードして」「スペースを保存」「スペースを落として」「スペースの録音」などと言われたら必ずこれを使う。ファイル名の末尾にホストのユーザー名を付ける。
---

# X のスペースを音声で保存する

yt-dlp が全部やる。ログイン・APIキー不要。録音が公開されているスペースだけが対象（終了後に録音が無効、または削除されていると取れない）。

## 手順

1. yt-dlp が無ければ `pip install -q yt-dlp`（ffmpeg は入っている）。
2. 先に CLAUDE.md の手順どおり `add_repo`（dik1-downloads, push）で接続し、clone 済みか確かめる。
3. 付属のスクリプトが、ホスト名の取得・ダウンロード・命名までやる（`yt-dlp` を直接組み立てない）:
   ```
   python3 /home/user/dik1/.claude/skills/x-space-download/x_space_download.py "<URL>" <出力ディレクトリ>
   ```
   - ファイル名は `タイトル_ホストの表示名.m4a`（例: `とりあえず聞け！集団戦のためになる話_MAD@大学教授が教える口説きの論理.m4a`）。表示名は yt-dlp の `uploader`で、`@ID` ではない。
   - 出力ディレクトリは scratchpad 内の空ディレクトリ。2時間級で 8〜10分かかるので、タイムアウトは 10分（600000ms）にする。
   - 録音が無いスペースは yt-dlp がエラーで止まる。
4. 100MB 以下なら `/home/user/dik1-downloads/downloads/` へコピーし（出力ディレクトリを直接 downloads/ にしてもよい）、CLAUDE.md どおり commit → `git pull --rebase origin main` → `git push origin HEAD:main`。
   - 100MB を超えたら push せず、渡し方をユーザーに確認する。
5. 返答には、保存したファイル名・長さ・サイズと「dik1-downloads の main へ push した（Mac のデスクトップへ自動で移る）」を書く。出力は音声1ファイルだけ（映像は無い）。

## 注意

- 作業ブランチ（claude/…）の未 push コミットが stop hook に指摘される。`git push -u origin <作業ブランチ>` も行う。
