---
name: notion-page-pdf
description: Notion の公開ページ（notion.site / notion.so の共有URL）を、本文・画像込みで PDF にして Mac へ渡す。notion.site/… のURLを渡されて「PDFにして保存」「Notionをダウンロード」「このページをPDFで」などと言われたら必ずこれを使う。URLだけが貼られたときも用途を聞き返さず落とす。ファイル名はページタイトル.pdf。
---

# Notion の公開ページを PDF にする

付属の `notion_page_pdf.py` が全部やる。Chromium（Playwright）で開き、遅延読み込みの画像を最後まで読ませ、1枚の縦長ページとして印刷し、画像を 110dpi に落とす（素のままだと 100MB 超になる。実績: 111MB → 9MB）。

```
python3 /home/user/dik1/.claude/skills/notion-page-pdf/notion_page_pdf.py "<URL>" /home/user/dik1-downloads/downloads
```

- 先に CLAUDE.md の手順どおり `add_repo`（dik1-downloads, push）→ 実行 → `git add downloads` → commit → `git pull --rebase origin main` → `git push origin HEAD:main`。
- 依存: `pymupdf`（`pip install pymupdf`）。Chromium は `/opt/pw-browsers/chromium`。
- 落とし穴: `waitUntil: 'networkidle'` は Notion では永久に来ずタイムアウトする。`domcontentloaded` + 待機で読む（スクリプトはそうしている）。
- 縦長になるのでページ（最大約 13,500pt）の切れ目で文章・画像が途中で分かれることがある。これは仕様。
- 返答前に冒頭と2ページ目を `pymupdf` で PNG にして目で確かめ、冒頭プレビューを `SendUserFile`（render）でチャットにも出す。
- 返答には保存したファイル名・サイズ・ページ数と「dik1-downloads の main へ push した（Mac のデスクトップへ自動で移る）」を書く。100MB を超えたら渡し方を確認する。
