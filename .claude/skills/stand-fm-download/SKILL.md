---
name: stand-fm-download
description: stand.fm のエピソードの音声を m4a でダウンロードして Mac へ渡す。stand.fm/episodes/… のURLを渡されて「この音声を保存」「stand.fm を落として」「standfm をダウンロード」などと言われたら必ずこれを使う。**stand.fm/episodes/… のURLだけが貼られたときも、用途を聞き返さずこのスキルで音声を落とす。**
---

# stand.fm のエピソードを音声で保存する

ログイン・APIキー不要。公開エピソードだけが対象（非公開・有料・削除済みは音声URLが取れない）。

## 手順

1. 先に CLAUDE.md の手順どおり `add_repo`（dik1-downloads, push）で接続し、clone 済みか確かめる。
2. 付属のスクリプトが、音声URLの特定・命名・ダウンロードまでやる:
   ```
   python3 /home/user/dik1/.claude/skills/stand-fm-download/stand_fm_download.py "<URL>" <出力ディレクトリ>
   ```
   - 出力ディレクトリは `/home/user/dik1-downloads/downloads/` でよい。
   - ファイル名は `エピソード名_チャンネル名.m4a`（例: `#60 エンビロンとゼオスキンどっちがいいの？_聴く美容液ラジオ.m4a`）。
   - ページ内には他エピソードの音声URLも混ざる。スクリプトは episodeId が一致するものだけを使う（`<audio src>` の最初を取るのは不可）。
3. 100MB 以下なら CLAUDE.md どおり commit → `git pull --rebase origin main` → `git push origin HEAD:main`。超えたら push せず、渡し方をユーザーに確認する。
4. 返答には、保存したファイル名・長さ・サイズと「dik1-downloads の main へ push した（Mac のデスクトップへ自動で移る）」を書く。長さは `ffprobe` か、ページ JSON の `duration`（ミリ秒）で出す。

## 注意

- 作業ブランチ（claude/…）の未 push コミットが stop hook に指摘される。`git push -u origin <作業ブランチ>` も行う。
