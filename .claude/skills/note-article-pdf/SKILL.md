---
name: note-article-pdf
description: note.com の記事（公開URL、または archive.li で保存した下書きプレビューのHTML）を、本文・画像・埋め込みリンク込みで PDF にして Mac へ渡す。note.com/…/n/n… のURLを渡されて「このnoteをダウンロードして」「noteをPDFにして」「note記事を保存」、または note.com/preview/… や archive.li の URL（下書きプレビュー）を渡されて「PDFでダウンロード」などと言われたら必ずこれを使う（プレビューURLは note_preview_pdf.py で自分で取れる。ユーザーにHTMLを頼まない）。x-article-pdf と同じルール（ファイル名＝記事タイトル、元URLの下に投稿日）。
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

## 下書きプレビュー（`note.com/preview/…?prev_access_key=…`）が来たとき

**通常版と同じ `note_article_pdf.py` にプレビューURLをそのまま渡す。** `prev_access_key` を付けて公開API（`/api/v3/notes/<キー>?prev_access_key=…`）を呼ぶと本文が取れる（ログイン不要）。ユーザーに HTML を頼まない。
```
python3 /home/user/dik1/.claude/skills/note-article-pdf/note_article_pdf.py "<プレビューURL>" /home/user/dik1-downloads/downloads
```
- 下書きは `publish_at` が空なので、投稿日は作成日（`created_at`、日本時間）で書く。
- 出力・ファイル名・PDFの中身は通常版と同じ。あとは `git add downloads` → commit → `git pull --rebase origin main` → `git push origin HEAD:main`。
- `note_preview_pdf.py`（Chromium で描画して取る方式）は、上記が失敗したときの予備。本文が取れないことが多い。

## archive.li で保存された HTML をユーザーが送ってきたとき（予備）

上のスクリプトが「本文が取れない」で失敗したときだけ、「Mac で archive.li のページを Cmd+S（ウェブページ、完全）で保存した HTML を送って」と頼む。受け取った HTML（`/root/.claude/uploads/…/*.html`）は:
```
python3 -I /home/user/dik1/.claude/skills/note-article-pdf/note_archive_pdf.py "<保存したhtml>" /home/user/dik1-downloads/downloads
```
- 先頭に「archive.li が◯◯に保存したもの」と注記が入る。以降は同じ手順で push。
