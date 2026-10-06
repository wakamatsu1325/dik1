---
name: x-article-pdf
description: X（旧Twitter）の記事（長文の Article）を、本文・画像・埋め込みポスト込みで PDF にして Mac へ渡す。x.com/…/status/… のURLを渡されて「この記事をダウンロードして」「記事をPDFにして」「Xの記事を保存」「記事を落として」などと言われたら必ずこれを使う。ポストが記事を含んでいるURLが対象。
---

# X の記事を PDF にする

付属の `x_article_pdf.py` が全部やる。ログイン・APIキー不要。標準 Python 3、curl、Chromium だけ（日本語フォント Noto Sans CJK JP が無ければ自動で入れる）。
**私の側では組み立て直さない。** URL を渡して走らせ、出力の要約行をそのまま伝える。

## 実行

```
python3 /home/user/dik1/.claude/skills/x-article-pdf/x_article_pdf.py "<x.com/.../status/数字 のURL>" /home/user/dik1-downloads/downloads
```

- 先に CLAUDE.md の手順どおり `add_repo`（dik1-downloads, push）で接続し、clone しておく。
- 出力は **PDF 1ファイルだけ**。Mac には PDF のみ渡す（Markdown・画像・zip は出さない）。
- ファイル名は記事タイトル（`/ \ : * ? " < > |` だけ `_` に置換）＋ `.pdf`。
- 実行後は CLAUDE.md どおり `git add downloads` → commit → `git pull --rebase origin main` → `git push origin HEAD:main`。Mac が前回分を削除していて modify/delete 競合になったら、`git add` で新しいPDFを残して `git rebase --continue`。

## PDF の中身

1. タイトル、著者、元URL、**元URLの下の行に投稿日**（記事の作成日時、日本時間）
2. 本文（見出し・段落）。プロンプト等のコードブロックは灰色の枠
3. 画像は元サイズ、図のキャプション付き
4. 埋め込みポストは X 風のカード（アイコン・名前・本文・動画サムネイルと再生マーク/秒数・引用元・日時・表示数/返信/リポスト/いいね/ブックマーク・URL）。動画は再生できない（サムネイルとURLのみ）。引用元が X 記事ならタイトルと冒頭だけ

## 仕組み・注意

- `api.fxtwitter.com/i/status/<ID>` の JSON の `tweet.article`（blocks / entityMap / media_entities）を読む。
- 画像は Python の urllib だと 403 になるので curl で取る。
- 記事のURL `x.com/i/article/…` だけでは引けない。記事を載せているポストのURLが要る。
- 結果の確認は `pdftoppm -r 60 -png -f 1 -l 1 <pdf> <接頭辞>` で1ページ目を画像にして見る。
