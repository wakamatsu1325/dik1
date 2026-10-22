---
name: images-to-one
description: 複数枚の画像（YouTube コミュニティ投稿の全画像など）を、1枚のグリッド画像にまとめる。「全画像を一枚の画像にして」「全部1枚にまとめて」「画像を結合して」と言われたら必ずこれを使う。YouTube の投稿URL（youtube.com/post/…）だけでなく、手元の画像群にも使う。
---

# 全画像を1枚にまとめる

## 手順

1. 画像が投稿URLなら、先に `yt-community-posts` の `yt_posts.rb` で取得する（`downloads/` に `高評価数_本文1行目_N.jpg` で落ちる）。
2. 結合する（既定は4列。7枚なら4×2で右下が白。セル幅780、全画像が同サイズ前提で1枚目の比率に合わせる）:

   ```bash
   python3 .claude/skills/images-to-one/scripts/grid.py "<高評価数_本文1行目>_全画像.jpg" downloads/<名前>_[1-9].jpg [--cols 4] [--cell-w 780]
   ```
   `_10` 以上があるときはファイル名を数字順に並べて渡す（glob の辞書順に注意）。
3. 出力は**フォルダに入れず、結合した1枚の画像だけ**を `dik1-downloads` の `downloads/` 直下へ置き、`main` へ push（CLAUDE.md の手順。だいきんぐの指定）。元の個別画像は送らない。
4. **`SendUserFile`（display: render）でチャットにも出す。**
5. 返答には、枚数・グリッド（列×行）・サイズ・保存名と「dik1-downloads の main へ push した（Mac のデスクトップ直下へ自動で移る）」。フォルダは作らないを書く。元画像は `dik1` にコミットしない。
