#!/usr/bin/env python3
"""_fonts.py — 找一个能渲中文的字体。被 gen-subs / make-cover / make-brand-assets 共用。

为什么要有这个：字幕和封面脚本原来写死了 macOS 的
`/System/Library/Fonts/STHeiti Medium.ttc`。别人在 Linux / Windows 上跑，
第一条命令就挂，而且报错只说「字体打不开」，不告诉你装什么。

查找顺序：
  1. 命令行 --font 显式指定
  2. 环境变量 VIDEO_CJK_FONT
  3. 本平台常见的中文字体（macOS / Linux / Windows 各一组）
  4. Linux 上 fc-match 兜底

单独跑它可以看当前机器找到了什么：
    python3 lib/_fonts.py
"""
import os
import subprocess
import sys

# 按「好看程度 + 常见程度」排。serif 组用于标题（宋体=分量感），sans 组用于正文。
CANDIDATES = {
    'sans': [
        # macOS
        '/System/Library/Fonts/STHeiti Medium.ttc',
        '/System/Library/Fonts/PingFang.ttc',
        '/System/Library/Fonts/Hiragino Sans GB.ttc',
        # Linux（Noto 是最容易装到的）
        '/usr/share/fonts/opentype/noto/NotoSansCJK-Medium.ttc',
        '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
        '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
        '/usr/share/fonts/google-noto-cjk/NotoSansCJK-Regular.ttc',
        '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc',
        '/usr/share/fonts/truetype/arphic/uming.ttc',
        # Windows
        'C:/Windows/Fonts/msyh.ttc',
        'C:/Windows/Fonts/msyhbd.ttc',
        'C:/Windows/Fonts/simhei.ttf',
    ],
    'serif': [
        '/System/Library/Fonts/Songti.ttc',
        '/System/Library/Fonts/STSong.ttf',
        '/usr/share/fonts/opentype/noto/NotoSerifCJK-Regular.ttc',
        '/usr/share/fonts/truetype/noto/NotoSerifCJK-Regular.ttc',
        '/usr/share/fonts/google-noto-cjk/NotoSerifCJK-Regular.ttc',
        'C:/Windows/Fonts/simsun.ttc',
    ],
    'latin': [
        '/System/Library/Fonts/Helvetica.ttc',
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        '/usr/share/fonts/dejavu/DejaVuSans.ttf',
        'C:/Windows/Fonts/arial.ttf',
    ],
}

INSTALL_HINT = """找不到中文字体。装一个再跑：
  Debian/Ubuntu : sudo apt-get install -y fonts-noto-cjk
  Fedora/RHEL   : sudo dnf install -y google-noto-sans-cjk-fonts
  Alpine        : apk add font-noto-cjk
  macOS         : 系统自带，不该走到这里
  或者直接指定： --font /path/to/your.ttf  （也可以设环境变量 VIDEO_CJK_FONT）
不装中文字体的话，字幕和封面会渲成一堆方框。"""


def _fc_match(pattern):
    """Linux 上问 fontconfig 要一个匹配的字体文件。"""
    try:
        out = subprocess.check_output(
            ['fc-match', '-f', '%{file}', pattern],
            stderr=subprocess.DEVNULL, timeout=5).decode().strip()
        return out if out and os.path.exists(out) else None
    except Exception:
        return None


def find_font(kind='sans', explicit=None):
    """返回一个存在的字体文件路径；找不到就抛 SystemExit 并给出安装提示。"""
    if explicit and os.path.exists(explicit):
        return explicit
    if explicit:
        print(f'  ! 指定的字体不存在：{explicit}，改用自动查找', file=sys.stderr)

    env = os.environ.get('VIDEO_CJK_FONT')
    if env and os.path.exists(env):
        return env

    for p in CANDIDATES.get(kind, []):
        if os.path.exists(p):
            return p
    # serif / latin 找不到就退回 sans，总比挂掉强
    if kind != 'sans':
        for p in CANDIDATES['sans']:
            if os.path.exists(p):
                return p

    hit = _fc_match('sans-serif:lang=zh') or _fc_match('serif:lang=zh')
    if hit:
        return hit

    sys.exit(INSTALL_HINT)


if __name__ == '__main__':
    print(f'平台: {sys.platform}')
    for k in ('sans', 'serif', 'latin'):
        try:
            print(f'  {k:6} → {find_font(k)}')
        except SystemExit as e:
            print(f'  {k:6} → 找不到\n{e}')
