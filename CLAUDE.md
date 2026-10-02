# このリポジトリでの約束

- ユーザーへの返答は必ず日本語で書く。フック（stop hook など）への対応報告や、英語のメッセージを受けた直後の返答も含め、例外なく日本語。

# downloads/ に置いたファイルは自動でMacのデスクトップへ届く

- クラウドセッションで、ユーザーに渡すファイルを `/home/user/dik1/downloads/`（リポジトリ直下の `downloads/`）へ保存したら、**その作業の終わりに必ず main へ push する**。Mac が1分以内に拾って、デスクトップ直下へ移す。
  ```
  git add downloads && git commit -m "downloads: <内容>" && git pull --rebase origin main && git push origin HEAD:main
  ```
- 作業ブランチ（`claude/...`）で作業していても、`downloads/` の変更だけは `main` へ直接 push してよい。
- Mac は受け取ったら `downloads/` の中身をリポジトリから削除（移動）する。削除のコミットは Mac が行うので、クラウドは触らない。
- 1ファイル 100MB 以下にする（GitHub の上限）。超えるものは、渡し方をユーザーに確認する。
- 保存後の返答には、保存したファイル名と「main へ push した（Mac のデスクトップへ自動で移る）」を書く。