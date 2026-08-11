#!/usr/bin/env python3
"""check-motion.py — 看一整条片子的镜头是不是「永远同一条路线」。

单看每一拍都合理，连起来看却是八拍一个套路 —— 这种问题只有把全片摊开才看得见，
所以它必须是一道**整片**检查，不是逐拍检查。真被打回过两次：
  第一次「你的缩放完全就是左右移动」  → 起终缩放不够，motion.sh 现在会单拍警告
  第二次「镜头永远是固定的路线」      → 每拍都从全屏推进某处，起点一模一样

框怎么算的不在这里重写 —— 调 `motion.sh --dry-run` 拿它自己算出来的起终框，
保证检查器和渲染器看到的是同一个镜头。

用法:
  /usr/bin/python3 lib/check-motion.py --project <dir> [--shots shots.tsv] [--strict]

退出码: 0 通过（含提示）/ 1 有硬问题（--strict 时提示也算）
"""
import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

AP = argparse.ArgumentParser()
AP.add_argument('--project', required=True)
AP.add_argument('--shots', default='shots.tsv')
AP.add_argument('--strict', action='store_true')
A = AP.parse_args()

proj = os.path.abspath(A.project)
shots = A.shots if os.path.isabs(A.shots) else os.path.join(proj, A.shots)
if not os.path.exists(shots):
    sys.exit(f'找不到 {shots}')

rows = []
for line in open(shots, encoding='utf-8'):
    if not line.strip():
        continue
    p = line.rstrip('\n').split('\t')
    while len(p) < 5:
        p.append('')
    rows.append(p)

texts = {}
cj = os.path.join(proj, 'clips.json')
if os.path.exists(cj):
    texts = {c['name']: c.get('text', '') for c in json.load(open(cj, encoding='utf-8'))}


def resolve(src):
    return src if os.path.isabs(src) else os.path.join(proj, src)


def boxes(src, extra):
    """调 motion.sh --dry-run 拿起终框。返回 (AW,AH,AX,AY,BW,BH,BX,BY,SW,SH,move) 或 None。"""
    cmd = [os.path.join(HERE, 'motion.sh'), src, '/dev/null',
           '--dur', '3', '--ss', '0'] + extra.split() + ['--dry-run']
    r = subprocess.run(cmd, capture_output=True, text=True)
    for ln in r.stdout.splitlines():
        if ln.startswith('BOX '):
            v = ln.split()
            return [int(x) for x in v[1:11]] + [v[11]]
    return None


def arrow(dx, dy, w, h):
    tx, ty = w * 0.06, h * 0.06
    return (('→' if dx > tx else '←' if dx < -tx else '·')
            + ('↓' if dy > ty else '↑' if dy < -ty else '·'))


beats, missing = [], []
for p in rows:
    name, kind, src, _ss, extra = p[0], p[1], p[2], p[3], p[4]
    if kind != 'motion':
        beats.append({'name': name, 'kind': kind, 'move': None})
        continue
    f = resolve(src)
    if not os.path.exists(f):
        missing.append(f'{name}: 素材不存在 {src}')
        continue
    b = boxes(f, extra)
    if not b:
        missing.append(f'{name}: motion.sh 算不出框（参数：{extra}）')
        continue
    AW, AH, AX, AY, BW, BH, BX, BY, SW, SH, move = b
    ca = (AX + AW / 2, AY + AH / 2)
    cb = (BX + BW / 2, BY + BH / 2)
    beats.append({
        'name': name, 'kind': kind, 'move': move,
        'full_start': AW >= SW - 4 and AH >= SH - 4,
        'dx': cb[0] - ca[0], 'dy': cb[1] - ca[1],
        'zr': AW / BW if BW else 1.0,
        'dir': arrow(cb[0] - ca[0], cb[1] - ca[1], SW, SH),
    })

mo = [b for b in beats if b['move']]
if not mo:
    print('  没有 motion 拍，跳过')
    sys.exit(0)

print(f'{"拍":>5} {"运动":>9} {"方向":>5} {"中心位移":>14} {"缩放":>7}  台词')
for b in beats:
    if not b['move']:
        print(f'  {b["name"]} {b["kind"]:>10} {"—":>6}{"":>16}{"":>9}  {texts.get(b["name"],"")[:16]}')
        continue
    z = ('推近' if b['zr'] > 1.1 else '拉远' if b['zr'] < 0.9 else '平移')
    print(f'  {b["name"]} {b["move"]:>10} {b["dir"]:>4} '
          f'{b["dx"]:+7.0f},{b["dy"]:+7.0f} {b["zr"]:5.2f}× {z}  {texts.get(b["name"],"")[:16]}')

hard, soft = list(missing), []
n = len(mo)

# ① 起点全是全屏 = 每一拍都「从全景推进去」，观众看到的永远是同一条路线
nfull = sum(1 for b in mo if b['full_start'])
if n >= 4 and nfull / n > 0.6:
    hard.append(f'{nfull}/{n} 拍从**全屏**起手 —— 每拍都是「全景推进某处」，'
                f'连起来就是同一条路线。用 --move pan --from <上一拍的落点> 接着走，'
                f'或者从局部拉开')

# ② 方向单一
dirs = {}
for b in mo:
    dirs[b['dir']] = dirs.get(b['dir'], 0) + 1
top, cnt = max(dirs.items(), key=lambda kv: kv[1])
if n >= 4 and cnt / n > 0.6:
    hard.append(f'{cnt}/{n} 拍的运动方向都是 {top} —— 换几拍反向或横移')

# ③ 全是推 / 全是拉
kinds = ['推近' if b['zr'] > 1.1 else '拉远' if b['zr'] < 0.9 else '平移' for b in mo]
if n >= 4 and kinds.count(kinds[0]) == n:
    hard.append(f'{n} 拍全是「{kinds[0]}」 —— 推-拉要有来有回，不然像单向滑轨')

# ④ 连续三拍完全同向
run, prev = 1, None
for b in mo:
    if prev is not None and b['dir'] == prev and b['dir'] != '··':
        run += 1
        if run >= 3:
            soft.append(f'{b["name"]} 之前连着 3 拍方向都是 {b["dir"]}，中间插一拍别的')
            run = 1
    else:
        run = 1
    prev = b['dir']

# ⑤ 一拍纯平移都没有：不是错，但整片会显得只会推拉
if n >= 5 and '平移' not in kinds:
    soft.append('全片没有一拍是纯平移（只缩放不移动 / 只移动不缩放）—— '
                '横着扫过一排东西，往往比再推一次更有信息量')

# ⑥ 缩放幅度太小（motion.sh 单拍也会警告，这里汇总）
# `hold` 不算 —— 它是明写的「这一拍镜头不动」。正当理由：**画面自己在动**
# （页面在滚、正文在往上走），这时候再推一下就是两层运动打架。
# 但整片不能到处是 hold，那就成了一串静态截图，所以下面卡比例。
weak = [b['name'] for b in mo
        if b['move'] != 'hold' and 0.8 < b['zr'] < 1.25
        and abs(b['dx']) < 60 and abs(b['dy']) < 60]
if weak:
    hard.append(f'{", ".join(weak)} 几乎没动（缩放 <1.25× 且中心不移）—— 等于静止画面。'
                f'真想让镜头定住就明写 --move hold，别用一个推不动的推镜假装')
nhold = sum(1 for b in mo if b['move'] == 'hold')
if n >= 4 and nhold / n > 0.3:
    hard.append(f'{nhold}/{n} 拍是 hold —— 镜头不动的拍太多，整片就是一串静态截图')

print()
for m in hard:
    print(f'  ✗ {m}')
for m in soft:
    print(f'  ! {m}')
print()
print(f'  {n} 拍有镜头运动 · 硬问题 {len(hard)} · 提示 {len(soft)}')
if hard:
    print('  → 镜头调完再渲。规矩见 skills/product-demo/ §三·五')
else:
    print('  → 镜头有变化。剩下的只有人能判：这一下移动是不是被台词带着走的。')
sys.exit(1 if hard or (A.strict and soft) else 0)
