#!/usr/bin/env python3
"""check-script.py — 口播稿（clips.json）机械自检。

配音前跑一次。硬错误退出码 1；软提示只是提醒，人工判断。

用法:
  /usr/bin/python3 lib/check-script.py --project <dir>
        [--rate 6.35]        # 含标点 字/秒。实测值见 skills/topic-and-script/
        [--target 40-60]     # 目标时长区间（秒）
        [--max-beat 15]      # 单拍时长上限（硬错误）——真正的约束是画面撑不撑得住
        [--strict]           # 软提示也算失败

语速实测值（含标点，写稿时数的就是这个）:
  克隆音 @1.10           4.98 字/秒
  presenter_male @1.30   6.35 字/秒   ← 默认
留出法校验（前 5 句拟合、预测后 4 句）误差 8.8% —— 估算只能到 ±10%，
所以配完音必须 ffprobe 实测一次。真实交付成片时长都落在 42–56s，别硬凑 90s。
"""
import argparse, json, os, re, sys

AP = argparse.ArgumentParser()
AP.add_argument('--project', help='工程目录（读 <dir>/clips.json）')
AP.add_argument('--clips', help='直接指定 clips.json')
AP.add_argument('--rate', type=float, default=6.35, help='含标点 字/秒，默认 presenter_male@1.30 实测值')
AP.add_argument('--target', default='40-60', help='目标时长区间，如 40-60')
# 硬约束是「一拍多长」，不是「一句多少字」——一拍 12s 就要准备 12s 连续画面。
# 实测：竖版 48s 片最长一拍 10.04s；横版 89s 片最长一拍 19.09s。
AP.add_argument('--max-beat', type=float, default=15.0, help='单拍时长上限（秒），超了算硬错误')
AP.add_argument('--warn-beat', type=float, default=8.0, help='单拍时长提示线（秒）')
AP.add_argument('--warn-chars', type=int, default=45, help='单句字数提示线（真实交付稿有 60-88 字的长句）')
AP.add_argument('--min-chars', type=int, default=6)
AP.add_argument('--strict', action='store_true')
A = AP.parse_args()

path = A.clips or (os.path.join(A.project, 'clips.json') if A.project else None)
if not path or not os.path.exists(path):
    sys.exit('找不到 clips.json。用 --project <dir> 或 --clips <path>')
clips = json.load(open(path, encoding='utf-8'))

try:
    tmin, tmax = (float(x) for x in A.target.split('-'))
except ValueError:
    sys.exit('--target 格式应为 40-60')

hard, soft = [], []


def nchar(t):                      # 纯汉字/数字/字母，不含标点
    return len(re.sub(r'[^\w]', '', t))


# ---------- 逐句 ----------
print(f"{'clip':8}{'字数':>5}{'纯字':>5}{'预估s':>7}  文本")
total = pure = 0.0
for i, c in enumerate(clips):
    name = c.get('name', f'#{i}')
    t = (c.get('text') or '').strip()
    n, np_ = len(t), nchar(t)
    total += n
    pure += np_
    est = n / A.rate
    head = t[:22] + ('…' if len(t) > 22 else '')
    print(f'{name:8}{n:>5}{np_:>5}{est:>7.1f}  {head}')

    if not t:
        hard.append(f'{name}: text 为空')
        continue
    if est > A.max_beat:
        hard.append(f'{name}: 这一拍预估 {est:.1f}s，超过 {A.max_beat:.0f}s —— '
                    f'你得准备这么长的连续画面，一般撑不住，拆句')
    elif est > A.warn_beat:
        soft.append(f'{name}: 这一拍 {est:.1f}s，确认素材够长（不够就 setpts 放慢，别切别的画面凑）')
    if n > A.warn_chars:
        soft.append(f'{name}: {n} 字，可能塞了多个信息点 —— 理想是一拍一个信息点；'
                    f'长句要保证句内标点够，字幕才切得开')
    if re.search(r'(^|[^A-Za-z])ta([^A-Za-z]|$)', t, re.I):
        hard.append(f'{name}: 出现 "ta" —— TTS 会念成字母 T-A，改成 他 / 她')
    if re.search(r'<#[\d.]+#>', t):
        soft.append(f'{name}: 带显式停顿标记，建议改用自然标点')
    if n < A.min_chars:
        soft.append(f'{name}: 只有 {n} 字，可能是碎句，考虑并进相邻句')

# ---------- 整体 ----------
est_total = total / A.rate
nclip = len(clips)
print()
print(f'  {nclip} 句 · {int(total)} 字（含标点）/ {int(pure)} 纯字 · '
      f'预估 {est_total:.1f}s @ {A.rate} 字每秒')

if nclip < 8 or nclip > 12:
    soft.append(f'句数 {nclip} —— 真实交付的片子都落在 8–12 句')
if est_total < tmin:
    soft.append(f'预估 {est_total:.1f}s 短于目标下限 {tmin:.0f}s')
if est_total > tmax:
    soft.append(f'预估 {est_total:.1f}s 超过目标上限 {tmax:.0f}s —— 抖音竖版 40–60s 最稳')

# 钩子具体性：第一句要有「人物 / 动作 / 数字」
if clips:
    h = (clips[0].get('text') or '')
    has_person = bool(re.search(r'[他她你我们那这][^\w]?|老板|朋友|对象|同事', h))
    has_num = bool(re.search(r'[0-9一二三四五六七八九十百千万第两半]', h))
    has_verb = bool(re.search(r'点开|翻|查|问|算|发|回|考|让|做|买|试|等|删|加|刷|存|欠|拼|冲', h))
    missing = [n for n, ok in (('具体的人', has_person), ('具体数字/时间', has_num), ('具体动作', has_verb)) if not ok]
    if missing:
        soft.append('钩子缺少 ' + ' / '.join(missing) +
                    ' —— 零 context 的观众要能在 3 拍内看懂发生了什么')
    if len(h) > 30:
        soft.append(f'钩子 {len(h)} 字 —— 心理/情感框的钩子建议 ≤25 砸得干脆；'
                    f'技术对比框要交代设置，长一点正常，自己判断')

# 末句要收品牌（实测：真实交付的末句往往是最长的一句，因为要把产品讲完 —— 所以不卡字数，卡有没有收）
if clips:
    last = (clips[-1].get('text') or '')
    if not re.search(r'[A-Za-z]{3,}|\.(net|com|cn)|官网|灵伴', last):
        soft.append('末句没有出现品牌名/网址 —— 最后一句一般用来收品牌')

# 开头重复用词：多句用同一个词起头 = 原地打转
starts = {}
for c in clips:
    t = (c.get('text') or '')
    if len(t) >= 2:
        starts.setdefault(t[:2], []).append(c.get('name'))
for k, v in starts.items():
    if len(v) >= 3:
        soft.append(f'{len(v)} 句都以「{k}」开头（{", ".join(v)}）—— 句式重复，读起来像原地打转')

# 框定话术
FRAMING = ['参考', '娱乐', '传统文化', '文化', '自我认知', '自我觉察', '换个角度',
           '你自己判断', '说法', '民俗', '国学']
alltext = ''.join((c.get('text') or '') for c in clips)
if not any(k in alltext for k in FRAMING):
    soft.append('全片没有框定话术 —— 建议至少一次把结果定性为「参考 / 换个角度认识自己 / 传统文化说法」')

# ---------- 输出 ----------
for m in hard:
    print(f'  ✗ {m}')
for m in soft:
    print(f'  ! {m}')
print()
print(f'  硬错误 {len(hard)} · 提示 {len(soft)}')
if hard:
    print('  → 有硬错误，改完再配音。规则见 skills/topic-and-script/SKILL.md')
elif soft:
    print('  → 没有硬错误。提示项人工判一下，不是每条都必须改。')
else:
    print('  → 干净。下一步：跑 check-compliance.py，再去配音。')
print('  ⚠ 预估时长只是估算 —— 配完音必须用 ffprobe 实测（lib/verify-audio.sh 会打印总时长）')

sys.exit(1 if hard or (A.strict and soft) else 0)
