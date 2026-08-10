#!/usr/bin/env python3
"""_fix_shots.py — make-placeholders.sh --footage 的辅助脚本，不用单独调。

做两件事：
  ① 把 shots.tsv 里**指向不存在文件**的行改到占位素材
  ② 补齐 clips.json 里有、但 shots.tsv 缺的拍

已经指向真素材的行一个字都不动。
缺行不补的话，build-vertical 会在第一个缺的拍上直接失败（真踩过：
init-project 的 shots.tsv 模板只有 3 行，写了 5 句就跑不动）。
"""
import json, os, sys

P = sys.argv[1]
sh = os.path.join(P, 'shots.tsv')
PICK = {
    'celeb': 'footage/ext/placeholder-horiz.mp4',
    'full':  'footage/rec/placeholder-vert.mp4',
    'card':  'html/beats/placeholder-card.mp4',
    'patch': 'footage/rec/placeholder-vert.mp4',
}

rows, changed = {}, 0
if os.path.exists(sh):
    for line in open(sh, encoding='utf-8'):
        f = line.rstrip('\n').split('\t')
        if len(f) >= 3 and f[0]:
            if not os.path.exists(os.path.join(P, f[2])):
                f = [f[0], f[1], PICK.get(f[1], PICK['card']), '0']
                changed += 1
            rows[f[0]] = (f + ['0'])[:4]

clips = [c['name'] for c in json.load(open(os.path.join(P, 'clips.json'), encoding='utf-8'))]
added = 0
for i, name in enumerate(clips):
    if name not in rows:
        kind = 'celeb' if i == 0 else ('card' if i % 2 else 'full')
        rows[name] = [name, kind, PICK[kind], '0']
        added += 1

order = clips + [c for c in rows if c not in clips]
open(sh, 'w', encoding='utf-8').write(
    '\n'.join('\t'.join(rows[c]) for c in order if c in rows) + '\n')
print(f'  shots.tsv: {changed} 行改到占位素材，补了 {added} 行缺的拍（真素材的行没动）')
