# このリポジトリでの約束

- ユーザーへの返答は必ず日本語で書く。フック（stop hook など）への対応報告や、英語のメッセージを受けた直後の返答も含め、例外なく日本語。

# downloads/ に置いたファイルは自動でMacのデスクトップへ届く

- ユーザーに渡すファイルは、**リポジトリ `wakamatsu1325/dik1-downloads` の `downloads/` に保存して、`main` へ push する**。Mac が1分以内に拾って、デスクトップ直下へ移す。`dik1` 自身には置かない（履歴が太るため）。
  - **最初に必ず `mcp__claude-code-remote__add_repo`（owner: wakamatsu1325, repo: dik1-downloads, access: push）でリポジトリをセッションに接続する。** 接続前の clone / push は毎回 403 で失敗するので、先に試さない（省略する）。
  - add_repo の結果の指示に従い、clone は1回だけ（`git clone --depth 1`、タイムアウトは長めの10分）。`/home/user/dik1-downloads` が既にあれば `git -C /home/user/dik1-downloads rev-parse HEAD` で生きているか確かめて、そのまま使う。clone 後に `register_repo_root` を呼ぶ。
  ```
  git clone --depth 1 https://github.com/wakamatsu1325/dik1-downloads.git /home/user/dik1-downloads  # add_repo の後、無ければ
  cp <ファイル> /home/user/dik1-downloads/downloads/
  cd /home/user/dik1-downloads && git add downloads && git commit -m "downloads: <内容>" && git pull --rebase origin main && git push origin HEAD:main
  ```
- Mac は受け取ったら `downloads/` の中身をリポジトリから削除（移動）する。削除のコミットは Mac が行うので、クラウドは触らない。
- 1ファイル 100MB 以下にする（GitHub の上限）。超えるものは、渡し方をユーザーに確認する。
- 保存後の返答には、保存したファイル名と「dik1-downloads の main へ push した（Mac のデスクトップへ自動で移る）」を書く。
- **画像を加工したら、必ず `SendUserFile`（display: render）でこのチャット内にも出す。** downloads/ への push だけで済ませない。チャットに出し忘れない。
