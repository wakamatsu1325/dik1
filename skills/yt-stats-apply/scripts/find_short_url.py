#!/usr/bin/env python3
# coding: utf-8
"""投稿本文・作品名・品番の断片から短縮URLを引く。

スクショの投稿名は末尾が「…」で切れているので、読めたところだけを渡す。
実行記録（runs/*.json）の text_a・images のパス・元URL（品番）と突き合わせる。
作品名で引けるようにしてあるのは、1枚目の画像の持ち主を入れるとき、
手元にあるのが投稿本文ではなく作品名だからである。
同じ投稿を作り直していると記録は複数あるが、短縮URLは1つに畳む。
"""
import glob
import json
import os
import re
import sys
import unicodedata

SUPPORT = os.path.join(os.path.expanduser('~'), 'Library', 'Application Support', 'Dog URL')
RUNS = os.path.join(SUPPORT, 'runs')


def normalize(text):
    # スクショから読んだ文字には 🉐/得 の揺れ・記号の欠けがあるので、記号は落として比べる。
    # 作品名には ☆ や全角の記号が混ざり、パスでは / が :: に化けているので、それも落とす。
    # macOSのファイル名は濁点が分かれた綴り（NFD）で来るので、先に揃える。揃えないと
    # 「シンデレラ」は合うのに「デ」を含む語で外れる。
    text = unicodedata.normalize('NFC', text)
    return re.sub(r'[\s【】🉐得！!？?👍😍👇…・.、。,☆★/:：\-ー―~〜「」『』()（）\[\]]', '', text)


def main(argv):
    if not argv:
        print('使い方: find_short_url.py <投稿本文・作品名・品番の断片> ...', file=sys.stderr)
        return 2

    hits = {}
    for path in sorted(glob.glob(os.path.join(RUNS, '*.json'))):
        try:
            with open(path, encoding='utf-8') as f:
                run = json.load(f)
        except (ValueError, OSError):
            continue
        short = run.get('short_url')
        if not short:
            continue
        text = (run.get('text_a') or '').strip()
        images = [i for i in (run.get('images') or []) if i]
        fields = [('本文', text)] if text else []
        fields += [('画像', images[0])] if images else []
        for needle in argv:
            key = normalize(needle)
            if not key:
                continue
            for where, value in fields:
                if key in normalize(value):
                    first = os.path.basename(images[0]) if images else ''
                    folder = os.path.basename(os.path.dirname(images[0])) if images else ''
                    hits.setdefault((short, text), (where, folder, first, os.path.basename(path)))
                    break

    if not hits:
        print('見つかりません（短縮URLを貼っていない投稿かもしれない）', file=sys.stderr)
        return 1

    for (short, text), (where, folder, first, run_file) in sorted(hits.items(), key=lambda kv: kv[0][0]):
        print('%s\t%s一致\t%s\t1枚目: %s/%s\t%s' % (
            short, where, text.replace('\n', ' '), folder, first, run_file[:8]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
