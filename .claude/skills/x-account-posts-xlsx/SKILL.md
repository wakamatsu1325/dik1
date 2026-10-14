---
name: x-account-posts-xlsx
description: X（旧Twitter）アカウントの全ポストを、日時・種別・本文・いいね数・リプ数・画像つきで、時系列（古い順）のExcelにまとめて Mac へ渡す。x.com/<ID> のプロフィールURLや @ID を渡されて「全てのポストと画像を時系列でエクセルにまとめて」「いいね数とリプ数を一覧に」「このアカウントの投稿を全部エクセルに」「投稿を一覧化」などと言われたら必ずこれを使う。単一ポストのURL（status/…）は x-video-download / x-article-pdf の担当で、こちらではない。
---

# X アカウントの全ポストをExcelにする

ログイン不要。fxtwitter の公開API（`api.fxtwitter.com/2/profile/<ID>/…`）を使う。

## 手順

1. CLAUDE.md の手順どおり、先に `add_repo`（dik1-downloads, push）で接続し、clone 済みか確かめる。
2. スクリプトを実行する（カーソルで最後まで辿るので数分かかる。timeout は長めに）:
   ```
   python3 -I /home/user/dik1/.claude/skills/x-account-posts-xlsx/x_account_posts_xlsx.py "<プロフィールURLか@ID>" <scratchpad内の空ディレクトリ>
   ```
   出力は `<表示名>_<ID>_全ポスト.xlsx`（表示名の絵文字は除く）。openpyxl と Pillow が要る。
3. **必ず1投稿だけ監査する。** 画像つきの1行を選び、`curl -s https://api.fxtwitter.com/i/status/<ID>` の値（日時・いいね・リプ・閲覧数・本文・画像URL）とExcelを突き合わせる。単体取得ではリポストは `retweets`、一覧では `reposts` と名前が違うだけ。
4. `.xlsx` を `/home/user/dik1-downloads/downloads/` へコピーし、CLAUDE.md どおり commit → `git pull --rebase origin main` → `git push origin HEAD:main`。
   - 前に送った同名ファイルを Mac が削除した直後だと `pull --rebase` が modify/delete で衝突する。`git add downloads` して `GIT_EDITOR=true git rebase --continue` で新しい版を残す。
5. 返答には、件数・種別の内訳・取得できなかった件数と「dik1-downloads の main へ push した（Mac のデスクトップへ自動で移る）」を書く。

## Excelの仕様（ユーザー指定済み）

- シートは**1枚だけ**。シート名は `名前_ID`（例: `のあちゃん_noa_dayo2004`）。「画像付きのみ」のような別シートは作らない。
- 時系列は古い順。列: No. / 投稿日時(JST) / 種別 / 本文 / いいね / リプ数 / リポスト / 閲覧数 / 画像 / 画像枚数 / **画像URL（残す）** / 投稿URL。
- 画像はサムネを埋め込む。複数枚は横に並べて1枚にする。動画はサムネ＋動画URL。
- 対象は本人の投稿・引用・リプライ。他人の投稿とリポストは除く。

## 落とし穴

- fxtwitter は断続的に 404 や空の結果を返す。スクリプトはリトライするので、1回の失敗で諦めない。
- 種別: `replying_to` が空で返る返信がある（本文が `@ID` で始まる）。「返信先あり」「本文が @ で始まる」「表示範囲の開始位置が0より後ろ」のどれかでリプライにする。`replying_to` だけで判定すると、返信が「ポスト」に紛れる。
- 通常のタイムラインは約100件で止まる。`with_replies=true` と `media` も辿って合算しないと古い投稿が漏れる。それでもアカウントの投稿数より少なく、削除済みなどは取れない。件数の差は返答で伝える。
