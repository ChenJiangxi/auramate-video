#!/usr/bin/env python3
"""check-rhythm.py — 把一条录屏的**节奏**摊开量：每一秒画面动了多少。

为什么要有这个：录屏最容易犯的错不是画质，是**节奏**。
匀速滚到底、开头不给人看清、一动就动十几秒 —— 单看每一帧都正常，
连起来观众就是"跟不上"。这条只有把整条片子摊平才看得见，跟 `check-motion.py` 同一个思路。

量法：抽小帧（96px 宽灰度），数相邻两帧里**真的变了的像素占多少**（默认灰度差 >12），
再按秒聚合，打成一条条形图。**不看内容，只看动/静的分布。**

为什么数占比不算平均差：粒子球、呼吸灯这类常驻动画是弥散的小幅抖动，
用平均差会被它抬高一个底噪，「一屏死内容 + 一个动画球」会被判成"全程都在动"，正好判反。

四条判据（都是从真实爆款和被打回的片子里量出来的）：

  1. 开头要定住     前 --head-hold 秒（默认 3s）几乎不动 —— 观众得先认出这是什么画面
  2. 要有动静交替   至少有一处停下来，也至少有一处在动
  3. 别当传送带     连续动很久**且强度恒定** = 匀速传送带。注意：连续滚很久本身不是错 ——
                    拿那条 5.5 万赞的量过，它连续滚了 24 秒，靠的是**滚动有快有慢**
                    （峰值/均值 2.60）。所以卡的是"又长又平"，不是"长"
  4. 别全程静止     一动不动的录屏和截图没区别

用法:
    /usr/bin/python3 lib/check-rhythm.py <video.mp4> [--head-hold 3] [--max-run 8]
                                         [--flat 1.30] [--still 1.2] [--fps 10]

    --still  变化像素占比低于这个百分数就算"静止"（默认 1.2%）

⚠ 页面有明显常驻动画（落地页的星点漂移、旋转圆环、循环入场）时，把 --still 调高：
   实测灵伴落地页要 `--still 2.0`，否则那点底噪会被当成"你在推着观众走"。
   判断方法：看节奏图里"什么都没操作"的那几秒是多少，把阈值定在它上面一点。

退出码：有硬问题返回 1，只有提示返回 0。
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

AP = argparse.ArgumentParser()
AP.add_argument('video')
AP.add_argument('--fps', type=float, default=10, help='分析用的采样帧率（不是源帧率）')
AP.add_argument('--head-hold', type=float, default=3.0, help='开头至少定住几秒')
AP.add_argument('--max-run', type=float, default=8.0,
                help='连续运动超过这么久，就要检查这段内部有没有快慢变化')
AP.add_argument('--flat', type=float, default=1.30,
                help='一段连续运动里 峰值/均值 低于这个数就算"匀速传送带"')
AP.add_argument('--still', type=float, default=1.2,
                help='变化像素占比低于这个百分数算静止')
AP.add_argument('--scale', type=int, default=160,
                help='分析用的缩略图宽度。太小会漏掉打字这种小面积变化')
AP.add_argument('--min-move', type=float, default=0.20,
                help='[scroll 模式] 运动秒数占比低于这个值 = 画面基本没在变')
AP.add_argument('--mode', default='scroll', choices=['scroll', 'event'],
                help='scroll=靠滚动推进（报告页）；event=靠事件推进（对话/表单型产品）')
AP.add_argument('--min-events', type=int, default=3, help='[event 模式] 至少几个明显事件')
AP.add_argument('--max-gap', type=float, default=5.0, help='[event 模式] 两个事件之间最多空几秒')
AP.add_argument('--delta', type=int, default=12,
                help='单个像素灰度差超过多少才算"变了"（压掉常驻动画的弥散抖动）')
AP.add_argument('--ffmpeg', default='ffmpeg')
A = AP.parse_args()

if not os.path.exists(A.video):
    sys.exit(f'找不到: {A.video}')
try:
    from PIL import Image
except ImportError:
    sys.exit('缺 Pillow。macOS 上用 /usr/bin/python3 跑。')

tmp = tempfile.mkdtemp(prefix='rhythm-')
try:
    subprocess.run([A.ffmpeg, '-nostdin', '-y', '-v', 'error', '-i', A.video,
                    '-vf', f'fps={A.fps},scale={A.scale}:-1,format=gray',
                    os.path.join(tmp, 'f%05d.png')], check=True)
    files = sorted(os.listdir(tmp))
    if len(files) < 4:
        sys.exit('帧太少，量不出节奏')
    prev = None
    diffs = []                      # 每个采样间隔的平均像素差
    for fn in files:
        im = Image.open(os.path.join(tmp, fn)).convert('L')
        px = list(im.getdata())
        if prev is not None:
            # 数「真的变了的像素占多少」，不是平均差。
            # 粒子球/呼吸灯那种常驻动画是**弥散的小幅**抖动（灰度差个位数），
            # 用平均差会被它抬起一个底噪；数超阈值的像素占比就能把它压回近 0，
            # 而文字出现、页面滚动这类**局部大幅**变化照样跳出来。
            chg = sum(1 for a, b in zip(px, prev) if abs(a - b) > A.delta)
            diffs.append(100.0 * chg / len(px))
        prev = px
finally:
    shutil.rmtree(tmp, ignore_errors=True)

step = 1.0 / A.fps
dur = (len(diffs) + 1) * step

# 按秒聚合
per_sec = []
for s in range(int(dur) + 1):
    win = [d for k, d in enumerate(diffs) if s <= (k + 1) * step < s + 1]
    if win:
        per_sec.append(sum(win) / len(win))

peak = max(per_sec) or 1.0
print(f'\n节奏图 · {os.path.basename(A.video)} · {dur:.1f}s · 采样 {A.fps}fps'
      f' · 静止阈值 {A.still}（自适应）\n')
for s, v in enumerate(per_sec):
    bar = '█' * int(round(v / peak * 46))
    tag = '静' if v < A.still else ''
    print(f'  {s:3d}s |{bar:<46}| {v:6.2f} {tag}')

# 静止阈值要**自适应**：页面上常有一直在动的东西（粒子球、loading、视频背景），
# 它把整条曲线抬高一个底噪。用低分位当基线，"静"= 贴着基线，而不是绝对值小。
# 不这么做的话，「一个动画球 + 一屏死内容」会被判成"全程都在动"，正好判反。
srt = sorted(per_sec)
base = srt[max(0, int(len(srt) * 0.2))] if srt else 0.0
thr = max(A.still, base * 1.25 + 0.15)
if base > A.still:
    print(f'  （页面有常驻动画，底噪 {base:.2f} —— 静止阈值自适应到 {thr:.2f}）\n')
still = [v < thr for v in per_sec]
moving = [not x for x in still]

# ---- 判据 ----
bad = 0
def ok(m):  print(f'  ✓ {m}')
def no(m):
    global bad
    print(f'  ✗ {m}'); bad += 1
def tip(m): print(f'  ! {m}')

print()
head = int(A.head_hold)
head_still = all(still[:head]) if len(still) >= head else False
if head_still:
    ok(f'开头 {head}s 定住了（观众来得及认出画面）')
else:
    first_move = next((i for i, m in enumerate(moving) if m), 0)
    # 入场动画（页面自己在渐显、元素飞入）和"被推走"不是一回事：
    # 前者是**衰减**的（越来越静），后者是持续的。落地页几乎都有入场动画，
    # 一律判失败会天天误报。
    seg = per_sec[:head + 1]
    settling = len(seg) >= 3 and seg[-1] < seg[0] * 0.6
    if settling:
        tip(f'开头 {first_move}s 就有动静，但强度在衰减（{seg[0]:.1f} → {seg[-1]:.1f}）——'
            f' 像页面自己的入场动画，不算把观众推走。确认一下不是你自己在滚')
    else:
        no(f'开头只定住了 {first_move}s，不够 {head}s —— 观众还没看清画面就被推走了')

frac = sum(moving) / max(1, len(moving))
if A.mode == 'scroll':
    if all(moving):
        no('全程都在动，一次都没停 —— 观众没有读的时间')
    elif frac < A.min_move:
        no(f'只有 {sum(moving)}/{len(moving)}s 画面在变（{frac:.0%}）—— 基本是张静态图，'
           f'观众没有理由留下。这条录屏缺"内容在生长"的那个发动机'
           f'（对话/表单型产品本来就没有滚动，加 --mode event 换一套判据）')
    else:
        ok(f'有动静交替（动 {sum(moving)}s / 静 {sum(still)}s，动占 {frac:.0%}）')
else:
    # 事件型：不看动占比，看「有几个看得见的事件」和「事件之间空多久」。
    # 对话/表单型产品没有可滚的长内容，节奏只能靠打字、提交、结果出现这些**事件**撑。
    evt_thr = max(1.0, base * 3 + 0.3)
    evts = [i for i, v in enumerate(per_sec) if v >= evt_thr]
    if len(evts) >= A.min_events:
        ok(f'有 {len(evts)} 个明显事件（第 {", ".join(str(e) + "s" for e in evts[:8])}）')
    else:
        no(f'只有 {len(evts)} 个明显事件，不够 {A.min_events} 个 —— '
           f'观众看不到"有事在发生"')
    # 开头那段刻意的"定住"由 head-hold 单独管，不算死时间 —— 从第一个事件开始数
    gaps = []
    prev_e = evts[0] if evts else 0
    for e in (evts[1:] if evts else []) + [len(per_sec)]:
        gaps.append((e - prev_e, prev_e, e)); prev_e = e
    worst = max(gaps, key=lambda g: g[0]) if gaps else (0, 0, 0)
    if worst[0] > A.max_gap:
        no(f'第 {worst[1]}–{worst[2]}s 空了 {worst[0]}s 什么都没发生 —— '
           f'这段多半是"等接口返回"的死时间，剪掉它，或者用强调层填上')
    else:
        ok(f'事件之间最长只空了 {worst[0]}s')

# 连续运动段：长不是问题，"又长又平"才是问题
runs, cur = [], []
for s_i, m in enumerate(moving):
    if m: cur.append(per_sec[s_i])
    elif cur: runs.append(cur); cur = []
if cur: runs.append(cur)
longest = max((len(r) for r in runs), default=0)
flat_bad = []
for r in runs:
    if len(r) > A.max_run:
        sp = max(r) / (sum(r) / len(r))
        if sp < A.flat: flat_bad.append((len(r), sp))
if flat_bad:
    for ln, sp in flat_bad:
        no(f'有一段连续动了 {ln}s 且强度几乎恒定（峰值/均值 {sp:.2f} < {A.flat}）'
           f' —— 这是匀速传送带。要么中间停一下让人读，要么把滚动分成快慢不同的几段')
else:
    ok(f'最长连续运动 {longest}s，段内有快慢变化（不是匀速传送带）')

# 全片的运动起伏
mv = [v for v in per_sec if v >= A.still]
if len(mv) >= 3:
    spread = max(mv) / (sum(mv) / len(mv))
    if spread < A.flat:
        tip(f'全片运动强度几乎恒定（峰值/均值 {spread:.2f}）—— 从头到尾一个速度')
    else:
        ok(f'全片运动有轻重变化（峰值/均值 {spread:.2f}）')

print(f'\n  {"RHYTHM OK" if not bad else f"RHYTHM FAIL ({bad} 条)"}\n')
sys.exit(1 if bad else 0)
