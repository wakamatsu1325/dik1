---
name: x-video-download
description: X（旧Twitter）の投稿に付いている動画を mp4 でダウンロードして Mac へ渡す。x.com/…/status/… のURLを渡されて「この動画を保存」「動画をダウンロード」「動画を落として」「Xの動画を取って」などと言われたら必ずこれを使う。URLだけ貼られて、用途を聞いて「動画を保存」と答えられた場合も同じ。ファイル名は「ユーザー名_投稿本文.mp4」。記事（Article）は x-article-pdf、スペースは x-space-download の担当で、こちらではない。
---

# X の投稿の動画を保存する

ログイン不要。fxtwitter の公開API（`api.fxtwitter.com`）で動画URLと本文を取り、最高ビットレートの mp4 を落とす。

## 手順

1. CLAUDE.md の手順どおり、先に `add_repo`（dik1-downloads, push）で接続し、clone 済みか確かめる。
2. 付属のスクリプトが、本文の取得・命名・ダウンロードまでやる:
   ```
   python3 /home/user/dik1/.claude/skills/x-video-download/x_video_download.py "<URL>" <出力ディレクトリ>
   ```
   - 出力ディレクトリは scratchpad 内の空ディレクトリ。
   - ファイル名は `ユーザー名_投稿本文.mp4`（例: `ganbaru_bonjin_【革命です】AI美女アプリが出来ました。.mp4`）。ユーザー名は `@` 抜きの screen_name。本文の改行は詰め、t.co のURLとファイル名に使えない文字（`/ \ : * ? " < > |`）は除く。120文字で切る。
   - 画質は、100MB 以下に収まる中で最高のものを自動で選ぶ（短い動画なら最高画質、長いと 720p などに落ちる）。全画質が超えるときは警告が出る。
   - 動画が複数あれば末尾に `_1` `_2` を付ける。
3. 100MB 以下なら `/home/user/dik1-downloads/downloads/` へコピーし、CLAUDE.md どおり commit → `git pull --rebase origin main` → `git push origin HEAD:main`。
   - 100MB を超えたら push せず、渡し方をユーザーに確認する。
   - 50MB を超えると GitHub が警告を出すが、push は通る。
4. 返答には、保存したファイル名・長さ・サイズと「dik1-downloads の main へ push した（Mac のデスクトップへ自動で移る）」を書く。

## 注意

- 作業ブランチ（claude/…）の未 push コミットが stop hook に指摘される。`git push -u origin <作業ブランチ>` も行う（dik1-downloads 側。clone は main から作業ブランチを切り直してよい）。
- 投稿が削除済み・動画なしのときはスクリプトが止まる。その旨を伝える。
