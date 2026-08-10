#!/usr/bin/env python3
"""check-humanness.py — 口播稿的「人味儿」检查：这段话听起来像人在说，还是像 AI 在念。

底层原理来自 renwei-writing（人味儿写作）：人味儿是三件事 ——
  位置：背后有一个具体的人，站在具体的位置说话
  代价：他为这个判断付过身体的代价（熬过夜、心动过、被气到）
  手迹：语气词、重复、不工整的呼吸，是他说话的样子

机器只能查第三层里最机械的部分：**AI 特有的句式痕迹**。
位置和代价查不了，所以最后会打印一份人工三问。

句式清单提炼自 Wikipedia「Signs of AI writing」（经 blader/humanizer, MIT），
按中文口播稿适配。

用法:
  python3 lib/check-humanness.py --project <dir>
  python3 lib/check-humanness.py --text "一段话"
  加 --strict 让提示也算失败
"""
import argparse, json, os, re, sys

AP = argparse.ArgumentParser()
AP.add_argument('--project')
AP.add_argument('--text')
AP.add_argument('--strict', action='store_true')
A = AP.parse_args()

# (正则, 名字, 为什么, 改法)
TELLS = [
    (re.compile(r'——|—'), '破折号',
     '最可靠的 AI 信号之一', '断成两句，或换成逗号/冒号'),
    (re.compile(r'不是.{1,12}，?而是'), '「不是X而是Y」',
     '最高频的 AI 假深刻', '直接说 Y，把 X 删掉'),
    (re.compile(r'与其说.{1,15}不如说|重要的不是.{1,12}而是'), '「不是X而是Y」的变体',
     '同上', '直接说结论'),
    (re.compile(r'(标志着|见证了|体现了|彰显了|折射出|印证了)'), '意义拔高',
     '把普通事实说成更大的东西', '事实说完就停，意义让观众自己长出来'),
    (re.compile(r'(璀璨|深厚底蕴|得天独厚|赋能|匠心|极致体验|不容错过|令人惊叹)'), '宣传腔',
     '中性内容写成了软文', '换成可验证的具体信息'),
    (re.compile(r'(未来可期|前景广阔|拭目以待|值得期待)'), '万能展望结尾',
     '结尾落在情绪上而不是事实上', '落在一个具体的东西上'),
    (re.compile(r'(让我们|接下来看看|话不多说|下面就来)'), '签到式过渡',
     '预告要说事，而不是直接说事', '删掉，直接说'),
    (re.compile(r'(说实话|老实讲|讲真)[，,]'), '假坦诚开场',
     '后面通常跟一个平平无奇的观点', '真坦诚的人直接说事'),
    (re.compile(r'[？?][^。！？\n]{0,8}[。！]'), '自问自答',
     '「结果呢？惨烈。」这种腔', '把答案直接说出来'),
]


def load():
    if A.text:
        return [('--text', A.text)]
    if not A.project:
        sys.exit('用 --project <dir> 或 --text "..."')
    p = os.path.join(A.project, 'clips.json')
    if not os.path.exists(p):
        sys.exit(f'找不到 {p}')
    return [(c['name'], c.get('text', '')) for c in json.load(open(p, encoding='utf-8'))]


rows = load()
hits = []
for name, t in rows:
    for rx, label, why, fix in TELLS:
        m = rx.search(t)
        if m:
            hits.append((name, label, m.group(0)[:16], why, fix))

# 手迹密度：一句语气词都没有，通常意味着念稿而不是说话
PARTICLES = ('吧', '呢', '啊', '嘛', '呗', '喽', '嘞', '哦')
alltext = ''.join(t for _, t in rows)
n_part = sum(alltext.count(p) for p in PARTICLES)
# 第一人称：有没有人站在那儿说话
n_me = alltext.count('我')

print(f'== 人味儿检查 —— {len(rows)} 句')
for name, label, frag, why, fix in hits:
    print(f'  ! {name}  {label}：「{frag}」')
    print(f'      {why} → {fix}')

soft = []
if n_part == 0:
    soft.append('全篇没有一个语气词（吧/呢/啊…）—— 书面语标准下它们"冗余"，'
                '但它们携带叹气、自嘲、犹豫。一个都没有通常是在念稿')
if n_me == 0:
    soft.append('全篇没有一个「我」—— 没人站在这段话背后。'
                '产品片尤其：讲"我为什么做这个"比讲"它有什么功能"有人味儿得多')
for s in soft:
    print(f'  ○ {s}')

print()
print(f'  句式痕迹 {len(hits)} 处 · 提示 {len(soft)} 条')
print('  机器只能查句式。剩下两件事只有人能判：')
print('    1. 位置 —— 这段话背后是谁？他站在哪儿说的？换个人说还成立吗？')
print('    2. 代价 —— 这些判断是他真经历过换来的，还是从词库里挑的？')
print('    3. 白描测试 —— 有没有更素、更直白的说法？往素里走不会把人改没。')

sys.exit(1 if (hits and A.strict) else 0)
