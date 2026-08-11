#!/usr/bin/env python3
"""cmp-frame.py — 取两个视频同一时刻的帧，打印平均像素差（0–255）。

给 tests/transitions-test.sh 用：判断「这一帧两版一不一样」。
0 附近＝同一画面（只有重编码噪声）；十几以上＝画面真的不同。

用法: cmp-frame.py A.mp4 B.mp4 <秒> [B的秒]
      第四个参数用于「两条片子有已知时移」的比较（例如加了前置停顿的镜头）。
"""
import subprocess
import sys
import tempfile
import os

if len(sys.argv) not in (4, 5):
    sys.exit(__doc__)
A, B, T = sys.argv[1], sys.argv[2], sys.argv[3]
TB = sys.argv[4] if len(sys.argv) == 5 else T

try:
    from PIL import Image, ImageChops
except ImportError:
    # 没装 Pillow 就退回 ffmpeg 自己算 —— 不想为一个比较把 Pillow 变成硬依赖
    out = subprocess.run(
        ['ffmpeg', '-nostdin', '-v', 'info', '-hide_banner', '-nostats',
         '-ss', T, '-i', A, '-ss', TB, '-i', B, '-frames:v', '1',
         '-filter_complex', '[0:v][1:v]blend=all_mode=difference,signalstats,'
                            'metadata=print:key=lavfi.signalstats.YAVG',
         '-f', 'null', '-'],
        capture_output=True, text=True).stderr
    for line in out.splitlines():
        if 'YAVG' in line:
            print(f'{float(line.split("=")[-1]):.2f}')
            sys.exit(0)
    sys.exit('比不了：既没有 Pillow，ffmpeg 也没给出 YAVG')


def grab(v, t):
    p = tempfile.mktemp(suffix='.png')
    subprocess.run(['ffmpeg', '-nostdin', '-y', '-v', 'error', '-ss', t, '-i', v,
                    '-frames:v', '1', p], check=True)
    im = Image.open(p).convert('RGB')
    im.load()
    os.unlink(p)
    return im


a, b = grab(A, T), grab(B, TB)
if a.size != b.size:
    sys.exit(f'尺寸不同 {a.size} vs {b.size}')
px = list(ImageChops.difference(a, b).getdata())
print(f'{sum(sum(t) for t in px) / (len(px) * 3):.2f}')
