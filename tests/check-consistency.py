#!/usr/bin/env python3
"""check-consistency.py — repo 级一致性检查。防的是「文档慢慢自相矛盾」这种慢性病。

查四件事：
  ① 孤儿脚本      lib/ 下没被任何 skill / README / references 提到的脚本
                  （`_` 开头的是内部辅助，豁免）
  ② 路由完整      每个 skill 都要能从 video-master 到达，否则 agent 找不到它
  ③ README 覆盖   README 目录表要列全所有 skill
  ④ 已推翻的说法  实测推翻过的旧口径不许在文档里复活

④ 是最重要的一条。这个 repo 的数值是一轮轮实测改出来的（语速 5→6.35、
单句 30 字上限被推翻、末句 15 字被推翻…），旧说法留在别处就会误导下一个 agent。
讲历史的地方（PROGRESS / 走查记录 / 明确写着「被推翻」的行）自动豁免。

用法: /usr/bin/python3 tests/check-consistency.py [repo_root]
退出码: 0 干净 / 1 有问题
"""
import os, re, sys

ROOT = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else
                       os.path.join(os.path.dirname(__file__), '..'))

# ---- 已被实测推翻的说法：正则 → (名字, 现在的正确口径) ----
DEBUNKED = [
    (re.compile(r'60\s*[–\-~]\s*90\s*s'),
     '目标时长 60–90s', '实测交付都落在 40–60s（Run 2 量的 6 条成片）'),
    (re.compile(r'单句\s*≤\s*30\s*字\s*[。.]'),
     '单句 ≤30 字（当硬上限写）', '真实交付稿有 43/61/88 字的句子；真约束是单拍时长'),
    (re.compile(r'[×x]\s*5(?!\d)\s*（?@?1\.28|目标时长\s*[×x]\s*5\b|≈\s*5\s*字/秒'),
     '语速 5 字/秒', '实测 6.35 字/秒（含标点，presenter_male@1.30）'),
    (re.compile(r'末句\s*≤\s*15\s*字'),
     '末句 ≤15 字', '实测末句常是全片最长的一句（要把产品讲完）'),
]
# 这些文件本来就是讲历史的
HISTORY_FILES = {'PROGRESS.md', 'zero-context-walkthrough.md'}
# 行内出现这些词说明是在引用旧说法并否定它
NEGATION = ('推翻', '不要迷信', '错的', '早期用', '被否', '已改', '曾经', '旧口径', '不是硬上限')

problems = []


def docs():
    for dp, dn, fn in os.walk(ROOT):
        dn[:] = [d for d in dn if d not in ('.git', 'work', 'node_modules', 'subs', 'audio', 'footage')]
        for f in fn:
            if f.endswith('.md'):
                yield os.path.join(dp, f)


# ---------- ① 孤儿脚本 ----------
libdir = os.path.join(ROOT, 'lib')
mention_blob = ''
for p in list(docs()):
    mention_blob += open(p, encoding='utf-8').read()
if os.path.isdir(libdir):
    for f in sorted(os.listdir(libdir)):
        if f.startswith('_') or f.startswith('.'):
            continue                       # 内部辅助，不要求出现在文档里
        if f not in mention_blob:
            problems.append(f'孤儿脚本 lib/{f} —— 没有任何文档提到它，agent 不会知道它存在')

# ---------- ② 路由完整 ----------
skdir = os.path.join(ROOT, 'skills')
skills = sorted(d for d in os.listdir(skdir) if os.path.isdir(os.path.join(skdir, d)))
master = open(os.path.join(skdir, 'video-master', 'SKILL.md'), encoding='utf-8').read()
for s in skills:
    if s == 'video-master':
        continue
    if f'skills/{s}/' not in master:
        problems.append(f'路由缺失 —— video-master 没提到 skills/{s}/，agent 到不了它')

# ---------- ③ README 覆盖 ----------
readme = open(os.path.join(ROOT, 'README.md'), encoding='utf-8').read()
for s in skills:
    if f'skills/{s}/' not in readme:
        problems.append(f'README 目录表缺 skills/{s}/')

# ---------- ④ 已推翻的说法 ----------
for p in docs():
    rel = os.path.relpath(p, ROOT)
    if os.path.basename(p) in HISTORY_FILES:
        continue
    for i, line in enumerate(open(p, encoding='utf-8'), 1):
        if any(w in line for w in NEGATION):
            continue
        for rx, name, correct in DEBUNKED:
            if rx.search(line):
                problems.append(f'旧说法复活 {rel}:{i} 「{name}」 → 现在的口径：{correct}')

print(f'  skills {len(skills)} 个 · 文档 {len(list(docs()))} 篇')
for p in problems:
    print('  ✗ ' + p)
if problems:
    print(f'  {len(problems)} 处不一致')
    sys.exit(1)
print('  一致性检查通过（无孤儿脚本 / 路由完整 / README 覆盖全 / 无旧说法复活）')
