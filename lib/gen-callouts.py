#!/usr/bin/env python3
"""gen-callouts.py — 生成「大字标注」PNG 序列 + manifest.tsv，交给 burn-subs.sh 压到成片上。

和字幕的区别（这是两层东西，别混）:

    字幕  = 口播的完整逐字稿，小字、贴底、每句都有、观众用来"听不清时看一眼"
    标注  = 3–8 个字的重点词，大字、居中偏上、一条片子只有 4–8 次、
            观众用来"扫一眼就知道这段在讲什么"

抖音上跑得动的产品/技术类视频几乎都是**双层文字**：底部小字幕 + 中部大红字。
大红字才是决定完播的那层 —— 观众划到你这条时先读大字，读懂了才留下听。
拆解见 `references/douyin-case-formsight.md`。

为什么不做成"再写一个 gen-subs"：产出的 manifest.tsv 格式和 gen-subs.py 完全一样
（png \\t start \\t end），所以 `burn-subs.sh --manifest a --manifest b` 一次压两层，
只编码一遍。

用法:
    /usr/bin/python3 lib/gen-callouts.py --callouts callouts.json --out callouts/ \\
        [--w 1920] [--h 1080] [--style slam|plain] [--y 0.34] [--font-size 96]

callouts.json（`at` / `dur` 都是**视频时间**秒；`\\n` 换行）:
    [
      {"at": 0.0,  "dur": 2.6, "text": "我把自己模拟出了3条人生线"},
      {"at": 3.4,  "dur": 4.0, "text": "不是星座\\n不是MBTI\\n不是算命"},
      {"at": 12.0, "dur": 2.4, "text": "默认线", "y": 0.5},
      {"at": 26.0, "dur": 3.0, "text": "评论区回复想看", "style": "plain"}
    ]

每条可覆盖: text / y（0–1 比例，画面高度）/ style / size / color。

样式:
    slam   红字 + 白描边 + 投影。抖音那种"手写标注"感，最抓眼，默认。
    plain  白字 + 黑描边。画面本来就花、红字会打架时用。

⚠ 别把标注放进画面最底下：1080 高的成片字幕带在 y≈924–982，压上去两层字会糊在一起。
   默认 y=0.34（偏上），和字幕天然分开。
"""
import argparse
import json
import os
import sys

AP = argparse.ArgumentParser()
AP.add_argument('--callouts', required=True, help='callouts.json 路径')
AP.add_argument('--out', default='callouts', help='PNG + manifest.tsv 的输出目录')
AP.add_argument('--w', type=int, default=1920)
AP.add_argument('--h', type=int, default=1080)
AP.add_argument('--y', type=float, default=0.34, help='默认竖直位置（0–1 比例），偏上避开字幕带')
AP.add_argument('--style', default='slam', choices=['slam', 'plain'])
AP.add_argument('--font-size', type=int, default=0, help='0 = 按画幅自动（宽的 5%%）')
AP.add_argument('--font', default=None)
AP.add_argument('--font-index', type=int, default=0)
AP.add_argument('--line-gap', type=float, default=1.22, help='行距倍数')
A = AP.parse_args()

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit('缺 Pillow。macOS 上用 /usr/bin/python3 跑（系统 python 自带 Pillow）；'
             '或 pip install Pillow')

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from _fonts import find_font                       # noqa: E402

FONT_PATH = find_font('sans', A.font)
SIZE = A.font_size or max(34, int(A.w * 0.05))     # 1920 → 96
try:
    FONT = ImageFont.truetype(FONT_PATH, SIZE, index=A.font_index)
except OSError:
    sys.exit(f'字体打不开: {FONT_PATH}')

# 红是抖音标注的默认色 —— 暗底亮底都跳得出来，且和大多数产品 UI 的主色不撞。
STYLES = {
    'slam':  dict(fill=(232, 58, 46, 255),  stroke=(255, 255, 255, 245), sw=max(3, SIZE // 12)),
    'plain': dict(fill=(248, 246, 240, 255), stroke=(0, 0, 0, 235),      sw=max(3, SIZE // 14)),
}

items = json.load(open(A.callouts, encoding='utf-8'))
if not isinstance(items, list) or not items:
    sys.exit('callouts.json 要是一个非空数组')

os.makedirs(A.out, exist_ok=True)
man_path = os.path.join(A.out, 'manifest.tsv')
man = open(man_path, 'w', encoding='utf-8')

prev_end = -1.0
for i, it in enumerate(items):
    text = str(it.get('text', '')).strip()
    if not text:
        print(f'  ! 第 {i + 1} 条没有 text，跳过', file=sys.stderr)
        continue
    at = float(it.get('at', 0))
    dur = float(it.get('dur', 2.4))
    if at < prev_end - 1e-6:
        # 两条标注叠在一起 = 画面上同时两块大字，观众不知道读哪个
        print(f'  ! 第 {i + 1} 条（{at}s）和上一条时间重叠了，画面会同时出现两块大字', file=sys.stderr)
    prev_end = at + dur

    st = dict(STYLES[it.get('style', A.style)])
    if it.get('color'):
        c = it['color'].lstrip('#')
        st['fill'] = tuple(int(c[j:j + 2], 16) for j in (0, 2, 4)) + (255,)
    size = int(it.get('size', SIZE))
    font = FONT if size == SIZE else ImageFont.truetype(FONT_PATH, size, index=A.font_index)

    img = Image.new('RGBA', (A.w, A.h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lines = text.split('\n')
    lh = int(size * A.line_gap)
    cy = int(A.h * float(it.get('y', A.y)))
    y0 = cy - (len(lines) - 1) * lh // 2
    for k, ln in enumerate(lines):
        # 投影单独画一层：只靠描边在亮底上会糊，加一层半透明黑影才立得住
        d.text((A.w // 2 + max(2, size // 28), y0 + k * lh + max(2, size // 28)), ln,
               font=font, fill=(0, 0, 0, 90), anchor='mm')
        d.text((A.w // 2, y0 + k * lh), ln, font=font,
               fill=st['fill'], stroke_width=st['sw'], stroke_fill=st['stroke'], anchor='mm')

    fn = os.path.join(A.out, f'k{i:03d}.png')
    img.save(fn)
    man.write(f'{os.path.abspath(fn)}\t{at:.3f}\t{at + dur:.3f}\n')

man.close()
n = sum(1 for _ in open(man_path, encoding='utf-8'))
print(f'rendered {n} callouts -> {man_path}  （{A.w}×{A.h} · {SIZE}px · {A.style}）')
print(f'下一步: lib/burn-subs.sh <in.mp4> <out.mp4> --manifest subs/manifest.tsv --manifest {man_path}')
