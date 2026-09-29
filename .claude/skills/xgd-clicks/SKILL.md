---
name: xgd-clicks
description: 他社（自分以外）の X.gd 短縮URLのクリック数を取る。x.gd/xxxxx を渡されて「クリック数分析して」「何クリック？」「伸び方は」と言われ、そのURLが自分の投稿（Dog URL の履歴・runs）に無いときに使う。累計と、過去24時間の1時間ごとのクリック数、流入元・国・端末の上位を出す。自分の投稿の伸びの分析（経過時間をそろえた順位づけ）は click-growth の担当で、こちらではない。
---

# 他社の X.gd URL のクリック数を取る

X.gd 公式の分析ページ `https://x.gd/analytics/<ID>`（`x.gd/<ID>+` でも飛ぶ）は、ログインなしで誰のURLでも見られる。
中身は `POST https://x.gd/api/v1/analytics` の結果。スクリプトは同じAPIを直接呼ぶ。

```bash
ruby ~/.claude/skills/xgd-clicks/clicks.rb x.gd/<ID>            # 過去24時間を1時間刻み
ruby ~/.claude/skills/xgd-clicks/clicks.rb x.gd/<ID> --days 7   # 過去7日を日刻み
```

出るもの: 分析ページのURL（`https://x.gd/analytics/<ID>`。答えの末尾にも必ず付ける）・作成時刻（UTC）・累計・読み取り時刻、時間別（日別）のクリック数、流入元・国・プラットフォームの上位5。

## 決まり

- **クリック数を取るだけ。** 自分の記録（`clicks.json` / `history.json`）には書かない。他社のURLは Dog URL の投稿ではない。
- 分析ページの `is_owner: false` は「自分のURLではない」の意味。他社のURLで正常。
- 1時間刻みで取れるのは**過去24時間まで**。作成から24時間を超えたURLの、序盤の時間別は取れない（日別になる）。
- 自分の投稿も 2026-09-29 から X.gd で発行している（それまでは TinyURL）。比べてよいのは自分の X.gd の投稿とだけで、それも参考値と断る。
  TinyURL 時代の自分の投稿は同じ回線のクリックを丸めて少なめなので、数を直接比べて優劣を言わない。
- APIの本文は `{id, mode:"last", range:"24", unit:"hour"|"day", timezone:"Asia/Tokyo", lang:"ja"}`。`range` は文字列。数値で送ると 400 になる。
