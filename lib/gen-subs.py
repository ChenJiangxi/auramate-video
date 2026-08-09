#!/usr/bin/env python3
"""gen-subs.py — 从 clips.json + 配音时长生成字幕 PNG 序列 + manifest.tsv。

为什么是 PNG 不是 ASS：很多 Homebrew ffmpeg 构建**不带 libass**（`ffmpeg -filters | grep ass`
返回空），`subtitles=`/`ass=` 滤镜直接报 "No such filter"。PNG overlay 路线零依赖、
所见即所得，代价是每行一张图 + 一条 overlay 链。想用 ASS 见 --emit-ass。

时间轴规则（必须和 build-vertical.sh 用同一个 GAP，否则整体漂移）：
    第 i 句起点 = Σ(前面每句配音时长 + GAP)
    句内按标点切子句，每个子句分到的时间 ∝ 它的字数

用法:
    /usr/bin/python3 lib/gen-subs.py --project <dir>
        [--y 1400] [--font-size 60] [--font "/System/Library/Fonts/STHeiti Medium.ttc"]
        [--gap 0.25] [--max-chars 15] [--skip c02,c03] [--w 1080] [--h 1920]
        [--emit-ass]

注意 macOS 上要用 **/usr/bin/python3**（系统 python 带 Pillow），
homebrew 的 python3 通常没装 PIL。
"""
import argparse, json, os, re, subprocess, sys

AP = argparse.ArgumentParser()
AP.add_argument('--project', required=True)
AP.add_argument('--audio-dir', default=None, help='默认 <project>/audio')
AP.add_argument('--out', default=None, help='默认 <project>/subs')
AP.add_argument('--w', type=int, default=1080)
AP.add_argument('--h', type=int, default=1920)
AP.add_argument('--y', type=int, default=1400, help='字幕基线 Y。竖版下三分之一 ≈1400，别贴底')
AP.add_argument('--font-size', type=int, default=60)
AP.add_argument('--font', default='/System/Library/Fonts/STHeiti Medium.ttc')
AP.add_argument('--font-index', type=int, default=0)
AP.add_argument('--gap', type=float, default=0.25)
AP.add_argument('--max-chars', type=int, default=15, help='一行最多几个字，超了就断行')
AP.add_argument('--no-merge', action='store_true',
                help='不合并短子句 —— 每个标点就是一次断行。钩子那句要用这个，'
                     '否则「他三天没回」+「你点开他的朋友圈」会被合成一行，三拍节奏就没了')
AP.add_argument('--skip', default='', help='逗号分隔的 clip 名，这些拍不叠字幕（画面自带大字时用）')
AP.add_argument('--stroke', type=int, default=7, help='黑描边宽度，竖版 60px 字用 7 刚好')
AP.add_argument('--ffprobe', default='ffprobe')
AP.add_argument('--emit-ass', action='store_true', help='额外产出 subs.ass（需要 ffmpeg 带 libass 才能烧）')
A = AP.parse_args()

P = os.path.abspath(A.project)
AUD = A.audio_dir or os.path.join(P, 'audio')
OUT = A.out or os.path.join(P, 'subs')
os.makedirs(OUT, exist_ok=True)
SKIP = {s.strip() for s in A.skip.split(',') if s.strip()}

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit('缺 Pillow。macOS 上用 /usr/bin/python3 跑这个脚本（系统 python 自带 Pillow）；'
             '或 pip install Pillow')

try:
    FONT = ImageFont.truetype(A.font, A.font_size, index=A.font_index)
except OSError:
    sys.exit(f'字体打不开: {A.font}\n  macOS 中文可用: /System/Library/Fonts/STHeiti Medium.ttc')


def dur(path):
    return float(subprocess.check_output(
        [A.ffprobe, '-v', 'error', '-show_entries', 'format=duration',
         '-of', 'csv=p=0', path]).decode().strip())


def split_lines(text, limit):
    """按标点切子句，再把短句合并到 limit 字以内（--no-merge 时不合并）。"""
    text = text.replace('——', '，').replace('—', '，')
    parts = [p.strip() for p in re.split(r'[，。！？、；：]', text) if p.strip()]
    if A.no_merge:
        return parts or ['']
    merged = []
    for p in parts:
        if merged and len(merged[-1]) + len(p) <= limit:
            merged[-1] += p
        else:
            merged.append(p)
    return merged or ['']


def render(text, fn):
    img = Image.new('RGBA', (A.w, A.h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.text((A.w // 2, A.y), text, font=FONT,
           fill=(245, 241, 233, 255), stroke_width=A.stroke,
           stroke_fill=(0, 0, 0, 235), anchor='mm')
    img.save(fn)


clips = json.load(open(os.path.join(P, 'clips.json')))
man_path = os.path.join(OUT, 'manifest.tsv')
man = open(man_path, 'w')
events = []          # for --emit-ass
idx = 0
acc = 0.0

for c in clips:
    name = c['name']
    apath = os.path.join(AUD, f'{name}.mp3')
    if not os.path.exists(apath):
        sys.exit(f'缺配音: {apath}')
    D = dur(apath)
    if name in SKIP:
        acc += D + A.gap
        continue
    lines = split_lines(c['text'], A.max_chars)
    tot = sum(len(l) for l in lines) or 1
    s = acc
    for i, l in enumerate(lines):
        seg = D * len(l) / tot
        end = acc + D if i == len(lines) - 1 else s + seg
        fn = os.path.join(OUT, f's{idx:03d}.png')
        render(l, fn)
        man.write(f'{fn}\t{s:.3f}\t{end:.3f}\n')
        events.append((s, end, l))
        s += seg
        idx += 1
    acc += D + A.gap

man.close()
print(f'rendered {idx} sub lines -> {man_path}  (末尾 {acc:.2f}s)')

if A.emit_ass:
    def ts(t):
        h = int(t // 3600); m = int((t % 3600) // 60); sec = t % 60
        return f'{h}:{m:02d}:{sec:05.2f}'
    # PlayResX/Y 必须写，否则 libass 默认 PlayResY=288，字号被隐式缩到看不见
    header = f"""[Script Info]
ScriptType: v4.00+
PlayResX: {A.w}
PlayResY: {A.h}
WrapStyle: 0
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,PingFang SC,{A.font_size - 2},&H00FFFFFF,&H000000FF,&H00000000,&H90000000,-1,0,0,0,100,100,0.5,0,1,3.5,1.5,2,100,100,{A.h - A.y},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
"""
    body = '\n'.join(f'Dialogue: 0,{ts(a)},{ts(b)},Default,,0,0,0,,{t}' for a, b, t in events)
    ass_path = os.path.join(OUT, 'subs.ass')
    open(ass_path, 'w').write(header + body + '\n')
    print(f'ass ok -> {ass_path}')
