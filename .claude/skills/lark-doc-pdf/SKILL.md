---
name: lark-doc-pdf
description: Lark / Feishu の公開ドキュメント（*.larksuite.com/docx/… や feishu.cn/docx/…）を、本文・画像込みの PDF にして Mac へ渡す。larksuite の docx URL を渡されて「PDFにして取得」「ダウンロード」「このドキュメントを保存」などと言われたら必ずこれを使う。URLだけが貼られたときも用途を聞き返さず落とす。ファイル名はドキュメントのタイトル.pdf。
---

# Lark ドキュメントを PDF にする

付属の `lark_doc_pdf.py` が全部やる（ログイン不要の公開リンク向け）。

```
python3 /home/user/dik1/.claude/skills/lark-doc-pdf/lark_doc_pdf.py "<URL>" /home/user/dik1-downloads/downloads
```

- 先に CLAUDE.md の手順どおり `add_repo`（dik1-downloads, push）→ 実行 → `git add downloads` → commit → `git pull --rebase origin main` → `git push origin HEAD:main`。Mac が前回ファイルを先に削除していて rebase で modify/delete 衝突したら、`git add downloads` して `GIT_EDITOR=true git rebase --continue`（新しい版を残す）。
- 依存: Playwright（node、`NODE_PATH=$(npm root -g)`）、Chromium は `/opt/pw-browsers/chromium`。
- 仕組み（変えない）:
  1. Lark は SPA で、スクロールしないと下のブロックと画像が描画されない（仮想化）。`.bear-web-x-container` を 500px ずつスクロールしながら、各ブロック（`[data-block-id]`、最上位のみ）の HTML を id 順に集め、画像は canvas で data URI にして埋め込む。
  2. 集めたブロックだけで自前の HTML を組み、A4 で印刷する。ページを直接 `page.pdf()` すると高さ固定のコンテナで 1 ページ分しか出ない。
  3. **余白対策（必須）**: 画像ブロックは `padding-top: 133.929%` と幅 1792px の固定指定で、そのまま印刷すると巨大な空白ができる。`.image-block-width-wrapper` / `.image-block-container` の幅・padding-top・height を解除し、`.resizable-wrapper` 配下は `position:static` にする。画像は `max-height:200mm`、画像ブロックは `break-inside:avoid`、空の段落は高さ 0.6em に潰す。実績: 24ページ → 12ページ。
- 返答前に先頭数ページを PNG にして目で確かめ、空白が残っていないか見る。冒頭プレビューを `SendUserFile`（render）でチャットにも出す。
- 返答には保存したファイル名・ページ数と「dik1-downloads の main へ push した（Mac のデスクトップへ自動で移る）」を書く。100MB を超えたら渡し方を確認する。
