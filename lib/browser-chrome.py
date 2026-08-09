#!/usr/bin/env python3
"""browser-chrome.py — 渲染一条假 Mac 浏览器壳（红黄绿灯 + 锁 + URL 药丸）。

裸录屏读起来像截图，不像产品。套一层壳立刻变成「这是一个真实存在的网站」。

用法:
  /usr/bin/python3 lib/browser-chrome.py --url "auramate.net" --path "/play/fate-match" \\
      --out assets/chrome-fate-match.png [--w 1920] [--h 120] [--theme dark]

每个片段的 URL 要跟着当前页面变 —— 这正是加壳的价值所在。
风格化卡片（hook / CTA）不加壳，它们是品牌美术不是界面。

用 PIL 而不是 HTML+浏览器截图：少一个 playwright 依赖，参数化更直接。
"""
import argparse, sys

AP = argparse.ArgumentParser()
AP.add_argument('--out', required=True)
AP.add_argument('--url', required=True, help='域名，例如 auramate.net')
AP.add_argument('--path', default='', help='路径，例如 /play/fate-match（灰色显示）')
AP.add_argument('--w', type=int, default=1920)
AP.add_argument('--h', type=int, default=120)
AP.add_argument('--theme', choices=['dark', 'light'], default='dark')
AP.add_argument('--font', default='/System/Library/Fonts/Helvetica.ttc')
A = AP.parse_args()

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit('缺 Pillow。macOS 用 /usr/bin/python3 跑；或 pip install Pillow')

W, H = A.w, A.h
if A.theme == 'dark':
    TOP, BOT = (42, 42, 44), (31, 31, 33)
    PILL = (46, 46, 49); PILL_EDGE = (58, 58, 62)
    TXT = (232, 232, 234); DIM = (157, 157, 159); LINE = (16, 16, 18)
else:
    TOP, BOT = (246, 246, 247), (233, 233, 235)
    PILL = (255, 255, 255); PILL_EDGE = (214, 214, 217)
    TXT = (32, 32, 34); DIM = (120, 120, 124); LINE = (200, 200, 204)

img = Image.new('RGB', (W, H), BOT)
d = ImageDraw.Draw(img)
# 竖向渐变
for y in range(H):
    t = y / max(1, H - 1)
    d.line([(0, y), (W, y)],
           fill=tuple(int(TOP[i] + (BOT[i] - TOP[i]) * t) for i in range(3)))

s = H / 120.0                      # 所有尺寸按高度等比缩放
dot_r = max(4, int(6 * s))
gap = int(14 * s)
x = int(24 * s)
cy = H // 2
for col in ((255, 95, 87), (255, 189, 46), (40, 200, 64)):
    d.ellipse([x - dot_r, cy - dot_r, x + dot_r, cy + dot_r], fill=col,
              outline=(0, 0, 0) if A.theme == 'dark' else (190, 190, 190))
    x += dot_r * 2 + gap

fs = max(10, int(20 * s))
try:
    font = ImageFont.truetype(A.font, fs)
except OSError:
    font = ImageFont.load_default()

domain, path = A.url, A.path
w_dom = d.textlength(domain, font=font)
w_path = d.textlength(path, font=font) if path else 0
lock_w = int(fs * 0.72)
inner = lock_w + int(10 * s) + w_dom + w_path
pill_w = max(int(W * 0.34), int(inner + 56 * s))
pill_h = int(44 * s)
px0 = (W - pill_w) // 2
py0 = cy - pill_h // 2
d.rounded_rectangle([px0, py0, px0 + pill_w, py0 + pill_h],
                    radius=int(9 * s), fill=PILL, outline=PILL_EDGE, width=max(1, int(s)))

# 锁：上面一个开口环 + 下面一个圆角方
tx = px0 + (pill_w - inner) // 2
lh = lock_w
ly = cy - lh // 2
body_top = ly + int(lh * 0.42)
d.rounded_rectangle([tx, body_top, tx + lock_w, ly + lh], radius=max(1, int(2 * s)), fill=DIM)
sh_pad = int(lock_w * 0.22)
d.arc([tx + sh_pad, ly, tx + lock_w - sh_pad, body_top + int(lh * 0.16)],
      start=180, end=360, fill=DIM, width=max(2, int(2.4 * s)))

tx += lock_w + int(10 * s)
d.text((tx, cy), domain, font=font, fill=TXT, anchor='lm')
if path:
    d.text((tx + w_dom, cy), path, font=font, fill=DIM, anchor='lm')

d.line([(0, H - 1), (W, H - 1)], fill=LINE, width=1)
img.save(A.out)
print(f'saved {A.out}  {W}x{H}  {A.theme}  "{domain}{path}"')
print('合成用法: lib/wrap-chrome.sh <录屏> <出片> --chrome ' + A.out + ' --dur <秒>')
