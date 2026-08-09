#!/usr/bin/env python3
"""make-brand-assets.py — 生成两张贴片：

  1. url-patch.png  —— 盖住旧录屏地址栏里的旧域名，写上正确域名。
     底色必须**精确匹配**原视频里地址栏药丸的 RGB，差一点就有色块痕迹。
     取色办法：ffmpeg -ss <秒> -i rec.mp4 -frames:v 1 /tmp/p.png，然后取药丸中心像素。

  2. brand-bug.png  —— 顶部品牌角标，外部素材段全程 overlay。

用法:
  /usr/bin/python3 lib/make-brand-assets.py --url auramate.net \
      --brand "✦ 品牌名" --pill-rgb 14,11,19 --out assets/
"""
import argparse, os, sys

AP = argparse.ArgumentParser()
AP.add_argument('--out', default='assets')
AP.add_argument('--url', required=True, help='正确的域名，例如 auramate.net')
AP.add_argument('--brand', default='', help='角标里的品牌名，可带前缀符号')
AP.add_argument('--pill-rgb', default='14,11,19', help='地址栏药丸底色 R,G,B —— 必须从原视频取真实值')
AP.add_argument('--patch-w', type=int, default=238)
AP.add_argument('--patch-h', type=int, default=38)
AP.add_argument('--patch-font-size', type=int, default=30)
AP.add_argument('--bug-w', type=int, default=1080)
AP.add_argument('--bug-h', type=int, default=110)
AP.add_argument('--bug-font-size', type=int, default=40)
AP.add_argument('--latin-font', default='/System/Library/Fonts/Helvetica.ttc')
AP.add_argument('--cjk-font', default='/System/Library/Fonts/STHeiti Medium.ttc')
A = AP.parse_args()

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit('缺 Pillow。macOS 用 /usr/bin/python3 跑；或 pip install Pillow')

os.makedirs(A.out, exist_ok=True)
try:
    PILL = tuple(int(x) for x in A.pill_rgb.split(','))
    assert len(PILL) == 3
except Exception:
    sys.exit('--pill-rgb 格式应为 R,G,B（如 14,11,19）')

# ---- 1. URL 补丁 ----
hel = ImageFont.truetype(A.latin_font, A.patch_font_size)
patch = Image.new('RGBA', (A.patch_w, A.patch_h), PILL + (255,))
pd = ImageDraw.Draw(patch)
pd.text((12, A.patch_h // 2), A.url, font=hel, fill=(206, 206, 208, 255), anchor='lm')
p1 = os.path.join(A.out, 'url-patch.png')
patch.save(p1)
print('url-patch:', patch.size, '->', p1)
print('  合成用法: -filter_complex "[0:v][1:v]overlay=<x>:<y>"   坐标每个素材单独量')

# ---- 2. 品牌角标 ----
if A.brand:
    zh = ImageFont.truetype(A.cjk_font, A.bug_font_size, index=0)
    W, H = A.bug_w, A.bug_h
    bug = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bug)
    dot = '   ·   '
    full = A.brand + dot + A.url
    tw = bd.textlength(full, font=zh)
    px, py = (W - tw) / 2, H / 2
    pad = 34
    bd.rounded_rectangle([px - pad, 18, px + tw + pad, H - 14], radius=42,
                         fill=(8, 8, 16, 150), outline=(255, 214, 140, 90), width=2)
    x = px
    for seg, col in ((A.brand, (255, 255, 255, 245)), (dot, (255, 255, 255, 120)), (A.url, (255, 206, 120, 255))):
        bd.text((x, py), seg, font=zh, fill=col, anchor='lm')
        x += bd.textlength(seg, font=zh)
    p2 = os.path.join(A.out, 'brand-bug.png')
    bug.save(p2)
    print('brand-bug:', bug.size, '->', p2)
    print('  合成用法: -filter_complex "[0:v][1:v]overlay=0:24"   外部素材段全程叠')
