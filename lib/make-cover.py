#!/usr/bin/env python3
"""make-cover.py — 爆款风竖版封面（巨字 + 戏剧图 + 副标 + 品牌 tag）。

macOS 上用 /usr/bin/python3 跑（系统 python 自带 Pillow）。

用法:
  /usr/bin/python3 lib/make-cover.py --bg assets/bg.png --out cover.png \
      --line1 "老外，都在算" --line2 "中国八字" \
      --sub "而 AI 算它，已逼近人类冠军" \
      --tag "品牌 · 一句定位"

设计要点（踩了 4 版视觉迭代定下来的）:
  · 即使内容讲论文，封面也必须爆款风，不能学术风
  · 顶部渐变压暗保证巨字可读；底部暗带托住 tag
  · 强调靠「换色」不靠「加粗」——缩略图里粗细看不出来
  · 每层文字都带黑描边，小屏不糊
"""
import argparse, os, sys

AP = argparse.ArgumentParser()
AP.add_argument('--bg', required=True, help='背景图。优先用成片抽帧：ffmpeg -ss N -i final.mp4 -frames:v 1 bg.png')
AP.add_argument('--out', default='cover.png')
AP.add_argument('--w', type=int, default=1080)
AP.add_argument('--h', type=int, default=1440, help='竖版 1080×1440；B站横版用 1920×1080')
AP.add_argument('--line1', required=True)
AP.add_argument('--line2', default='', help='强调行，用高亮色')
AP.add_argument('--sub', default='')
AP.add_argument('--tag', default='')
AP.add_argument('--font', default='/System/Library/Fonts/STHeiti Medium.ttc')
AP.add_argument('--font-index', type=int, default=0)
AP.add_argument('--size-big', type=int, default=154)
AP.add_argument('--size-sub', type=int, default=58)
AP.add_argument('--size-tag', type=int, default=46)
AP.add_argument('--accent', default='#F0BE56', help='高亮色（第二行 + 分隔线 + tag）')
A = AP.parse_args()

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit('缺 Pillow。macOS 用 /usr/bin/python3 跑；或 pip install Pillow')

W, H = A.w, A.h
ACCENT = tuple(int(A.accent.lstrip('#')[i:i+2], 16) for i in (0, 2, 4))
WHITE, CREAM = (246, 244, 239), (231, 225, 213)

if not os.path.exists(A.bg):
    sys.exit(f'背景图不存在: {A.bg}\n  可从成片抽帧: ffmpeg -ss <秒> -i final.mp4 -frames:v 1 {A.bg}')

img = Image.open(A.bg).convert('RGB')
# 等比填满再居中裁到目标尺寸
r = max(W / img.width, H / img.height)
img = img.resize((max(1, int(img.width * r)), max(1, int(img.height * r))), Image.LANCZOS)
img = img.crop(((img.width - W) // 2, (img.height - H) // 2,
                (img.width - W) // 2 + W, (img.height - H) // 2 + H))

base = img.convert('RGBA')
ov = Image.new('RGBA', (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(ov)
# 顶部渐变压暗：alpha 从 ~221 递减到 46，保证巨字在任何背景上都读得清
for y in range(H):
    t = y / (H * 0.60)
    a = int(175 * max(0.0, 1.0 - t)) + 46
    d.line([(0, y), (W, y)], fill=(6, 5, 12, min(a, 255)))
# 底部暗带托住 tag
band = int(H * 0.195)
for y in range(H - band, H):
    a = int(160 * ((y - (H - band)) / band))
    d.line([(0, y), (W, y)], fill=(6, 5, 12, a))
base = Image.alpha_composite(base, ov)
draw = ImageDraw.Draw(base)


def font(sz):
    try:
        return ImageFont.truetype(A.font, sz, index=A.font_index)
    except OSError:
        sys.exit(f'字体打不开: {A.font}')


def center(y, text, f, fill, sw=8):
    draw.text((W // 2, y), text, font=f, fill=fill, stroke_width=sw,
              stroke_fill=(0, 0, 0), anchor='mm')


FB, FS, FT = font(A.size_big), font(A.size_sub), font(A.size_tag)
y1 = int(H * 0.25)
center(y1, A.line1, FB, WHITE)
y = y1
if A.line2:
    y = y1 + int(A.size_big * 1.1)
    center(y, A.line2, FB, ACCENT)
if A.sub:
    ry = y + int(A.size_big * 0.72)
    draw.line([(W // 2 - 190, ry), (W // 2 + 190, ry)], fill=ACCENT, width=4)
    center(ry + int(A.size_sub * 1.32), A.sub, FS, CREAM, sw=5)
if A.tag:
    center(H - int(H * 0.067), A.tag, FT, ACCENT, sw=4)

base.convert('RGB').save(A.out, quality=95)
print('saved', A.out, f'{W}×{H}')
n = len(A.line1) + len(A.line2)
if n > 12:
    print(f'⚠ 巨字共 {n} 字（建议 ≤12）—— 字多就得降字号，冲击力会掉')
