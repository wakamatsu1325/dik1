---
name: note-article-pdf
description: note.com の記事を、本文・画像・埋め込みリンク込みで PDF にして Mac へ渡す。note.com/…/n/n… のURLを渡されて「このnoteをダウンロードして」「noteをPDFにして」「note記事を保存」などと言われたら必ずこれを使う。x-article-pdf と同じルール（ファイル名＝記事タイトル、元URLの下に投稿日）。
---

# note の記事を PDF にする

付属の `note_article_pdf.py` が全部やる。ログイン不要（`note.com/api/v3/notes/<キー>` の公開JSON）。curl と Chromium だけ。
**私の側では組み立て直さない。** URL を渡して走らせ、出力の要約行をそのまま伝える。

```
python3 /home/user/dik1/.claude/skills/note-article-pdf/note_article_pdf.py "<note.com/…/n/n… のURL>" /home/user/dik1-downloads/downloads
```

- 先に CLAUDE.md の手順どおり `add_repo`（dik1-downloads, push）→ 実行 → `git add downloads` → commit → `git pull --rebase origin main` → `git push origin HEAD:main`。
- 出力は **PDF 1ファイルだけ**。ファイル名は記事タイトル（`/ \ : * ? " < > |` だけ `_` に置換）＋ `.pdf`（x-article-pdf と同じ）。
- PDF の中身: タイトル、著者、元URL、**元URLの下の行に投稿日**（日本時間）、本文、画像（元サイズ）、埋め込みリンクはカード（タイトル・説明・URL）。
- 有料記事は無料公開部分のみ（末尾に注記）。
- 確認は `pdftoppm -r 60 -png -f 1 -l 1 <pdf> <接頭辞>` で1ページ目を見る。
