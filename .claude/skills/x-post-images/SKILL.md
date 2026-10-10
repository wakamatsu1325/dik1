---
name: x-post-images
description: X（旧Twitter）の投稿に付いている画像を原寸で保存して Mac へ渡す。x.com/…/status/… のURLを渡されて「画像を保存」「画像を落として」「この投稿の画像」などと言われたら使う。**x.com/…/status/… のURLだけが貼られ、fxtwitter の JSON に `tweet.media.photos` があって動画・記事・スペースが無いときは、聞き返さずこれで画像を落とす。** 動画は x-video-download、記事は x-article-pdf、スペースは x-space-download の担当。YouTube のコミュニティ投稿（youtube.com/post/…）は yt-community-posts。
---

# X の投稿の画像を保存する

yt-community-posts の個別投稿と同じ扱い。ログイン不要、fxtwitter の公開API。

## 手順

1. CLAUDE.md の手順どおり、先に `add_repo`（dik1-downloads, push）で接続し、clone 済みか確かめる。
2. スクリプトを走らせる（出力ディレクトリは scratchpad 内の空ディレクトリ）:
   ```
   python3 /home/user/dik1/.claude/skills/x-post-images/x_post_images.py "<URL>" <出力ディレクトリ>
   ```
   - 画像を `いいね数_本文1行目` フォルダにまとめる（画像名は `いいね数_本文1行目_N.拡張子`。t.co 等のURLと使えない文字は除く）。画像は `?name=orig` の原寸。
   - 最後に本文のリンク（展開済み）を `本文リンク: URL` で出す。
3. フォルダごと `/home/user/dik1-downloads/downloads/` へコピーし、commit → `git pull --rebase origin main` → `git push origin HEAD:main`。画像だけを `downloads/` 直下に並べない。
4. **画像を `SendUserFile`（display: render）でチャットにも出す**（push だけで終わらせない）。
5. 画像の後に、本文リンクをチャットへ出す。**出すのは本文のリンクだけ**（転送先は踏まない・書かない）。リンクが無いときは、その旨を一言書く。
6. 返答には、フォルダ名と「フォルダごと dik1-downloads の main へ push した（Mac のデスクトップへ自動で移る）」を書く。

## 注意

- 画像が無い投稿はスクリプトが止まる。その旨を伝える。
- 動画も付いている投稿は、x-video-download も併せて走らせる。
