---
name: vertical-shortform
description: 竖版短视频（抖音/小红书 1080×1920，60–90s）的完整执行管线——从 clips.json 到交付包。包含逐拍编码、audio-driven 时间轴、concat、mux 的可直接复制脚本。触发词：竖版、抖音、小红书、短视频、60秒、90秒、出一条片、混剪成片。
---

# vertical-shortform — 竖版短视频完整管线

这是主干 skill。90% 的片子走这条路。先读 `skills/video-master/SKILL.md` 的硬规矩，再回来执行。

**输出规格**：1080×1920 / 30fps / yuv420p / H.264 CRF 19 / AAC 192k / `+faststart`

---

## 项目目录结构（照建，脚本按这个找文件）

```
<project>/
├── clips.json          # ① 单一事实源：分句口播稿
├── topic.md            # 选题：钩子 + 为什么能火 + 落到什么功能
├── audio/              # ② 配音 c01.mp3 c02.mp3 ...
│   └── samples/        #    音色候选采样（给人类挑）
├── footage/            # ③ 素材
│   ├── ext/            #    外部真人切片（yt-dlp 下的）
│   └── rec/            #    产品录屏
├── html/               # ④ 动效卡源码 + render.js
├── assets/             # ⑤ 品牌角标 / 补丁图 / 封面
├── work/               # ⑥ 中间产物（逐拍 vNN.mp4、concat 清单）
├── subs/               # ⑦ 字幕 png + manifest.tsv（或 subs.ass）
├── build.sh            # 合成脚本
├── burn-subs.sh        # 烧字幕
└── deliver-<slug>/     # ⑧ 交付包内容
```

初始化：

```bash
lib/init-project.sh <project-dir>
```

---

## 阶段 ① 选题 → `topic.md`

写清三件事，缺一不可：

```markdown
## 钩子（第一句口播，≤ 25 字）
他三天没回。你点开他的朋友圈，第十七次。

## 为什么这条能火
点破「刚动心就偷偷查对方」这个人人做过、没人明说的隐秘行为。

## 落到什么功能
缘分匹配 /play/fate-match —— 合盘评分 + 多维度拆解，跟「他到底喜不喜欢我」严丝合缝。
```

**选题→功能必须对得上。** 讲财运就落财运报告，不是随手一个别的功能。这条被专门挑过。

---

## 阶段 ② 脚本 → `clips.json`

```json
[
 {"name":"c01","text":"DeepSeek 今天刚发了正式版 V4。我让它，和老款 R1，算同一个八字，看谁准。"},
 {"name":"c02","text":"生辰是公历 1998 年 3 月 15 日上午 10 点。正确答案是——戊寅、乙卯、辛酉、癸巳，日主辛金。"},
 {"name":"c09","text":"这才是认真算命该有的样子。"}
]
```

规矩：

- 一句 = 一个镜头 = 一段配音。**别把两个画面塞进一句。**
- 单句 ≤ 30 字。长句 TTS 会喘不上气，字幕也放不下。
- 总字数 ≈ 目标时长 × 5（@1.28 倍速）。75s ≈ 375 字。
- 写 `他/她`，不写 `ta`（TTS 会念字母）。
- 第一句就是钩子，具体到人物+动作+数字。
- 最后一句收品牌，别超过 15 字。

写完自查字数：

```bash
python3 -c "
import json,sys
c=json.load(open('clips.json'))
t=sum(len(x['text']) for x in c)
print(f'{len(c)} 句 / {t} 字 / 预估 {t/5:.0f}s @1.28x')
for x in c:
    if len(x['text'])>30: print('  ⚠ 过长:', x['name'], len(x['text']), '字')
"
```

---

## 阶段 ③ 素材 → `footage/`

每句台词都要有对应画面。先列一张**镜头表**，再去找素材：

| clip | 台词要点 | 画面 | 来源 |
|---|---|---|---|
| c01 | DeepSeek 排八字 | 模型输出界面切片 | `footage/ext/ai-deepseek.mp4` |
| c05 | 排盘差了一天 | 命盘界面 | 产品录屏 |

三种来源分别跳去：`skills/real-clip-mashup/` · `skills/product-demo/` · `skills/html-motion-cards/`

**素材长度必须 ≥ 对应配音时长**，不然那一拍会黑屏。不够长就放慢（`setpts`），别切别的画面凑。

---

## 阶段 ④ 配音 → `audio/cNN.mp3`

见 `skills/tts-voiceover/`。要点：

```bash
# 先出音色采样给人类挑
node lib/gen-voice.mjs --sample --text "第一句口播" --out audio/samples/

# 定了音色再全量生成
MINIMAX_API_KEY=... node lib/gen-voice.mjs --clips clips.json --out audio/ --voice presenter_male --speed 1.28
```

生成后**必须逐个检查文件非空**——TTS 失败会写出 0 字节文件，后面 concat 悄悄少一拍：

```bash
lib/verify-audio.sh audio/ clips.json
```

---

## 阶段 ⑤ 合成 → `<slug>-nosub.mp4`

核心是 **audio-driven**：先量配音时长，再决定每一拍视频多长。

```bash
GAP=0.25
for c in c01 c02 c03 ...; do
  dc=$(ffprobe -v error -show_entries format=duration -of csv=p=0 audio/$c.mp3)
  eval "T_$c=$(echo "$dc+$GAP" | bc)"
done
```

### 四个逐拍编码器（按素材类型选一个）

统一后缀 `V="fps=30,setsar=1,format=yuv420p"`。**每个都必须 `-an`**（音轨最后统一拼，
逐拍带音轨会导致 concat 音画错位）。

**A. 静态卡 / 已经是竖版的渲染物**

```bash
enc_card(){ ffmpeg -nostdin -y -v error -i "$1" -t "$2" \
  -vf "scale=1080:1920:flags=lanczos,$V" -an -c:v libx264 -crf 19 -pix_fmt yuv420p "$3"; }
# 用法: enc_card html/beats/bench.webm $T_c02 work/v02.mp4
```

**B. 横屏真人切片 → 竖版**（模糊背景垫底 + 主体等比居中，保留源水印字幕 = 真实混剪质感）

```bash
enc_celeb(){ ffmpeg -nostdin -y -v error -ss "$4" -t "$2" -i "$1" -vf \
  "split=2[a][b];\
   [a]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=26:3,eq=brightness=-0.34:saturation=0.66[bg];\
   [b]scale=1080:820:force_original_aspect_ratio=decrease,unsharp=5:5:0.6[fg];\
   [bg][fg]overlay=(W-w)/2:440,$V" \
  -an -c:v libx264 -crf 19 -pix_fmt yuv420p "$3"; }
# 用法: enc_celeb footage/ext/ai-deepseek.mp4 $T_c01 work/v01.mp4 2   # 最后一个 = 起始秒
```

**C. 竖版录屏 / 竖版素材，整屏铺满**

```bash
enc_full(){ ffmpeg -nostdin -y -v error -ss "$4" -t "$2" -i "$1" \
  -vf "scale=1080:1920:flags=lanczos,unsharp=7:7:0.9,$V" \
  -an -c:v libx264 -crf 19 -pix_fmt yuv420p "$3"; }
```

**D. 录屏 + 打补丁 + 裁切放大**（盖旧域名、裁掉留白）

```bash
enc_patch(){ ffmpeg -nostdin -y -v error -ss 2 -t "$2" -i "$1" -i assets/url-patch.png \
  -filter_complex "[0:v][1:v]overlay=428:576[p];\
                   [p]crop=1080:1000:0:440,pad=1080:1920:0:250,unsharp=5:5:0.6,$V[v]" \
  -map "[v]" -an -c:v libx264 -crf 19 -pix_fmt yuv420p "$3"; }
```

> `overlay=428:576` 和 `crop` 的坐标是**每个素材单独量出来的**，不是通用值。
> 量法：`ffmpeg -ss 3 -i src.mp4 -frames:v 1 /tmp/probe.png` 然后看图取坐标。

### concat 视频

```bash
> work/vl.txt
for i in 01 02 03 04 05 06 07 08 09; do echo "file 'work/v$i.mp4'" >> work/vl.txt; done
ffmpeg -nostdin -y -v error -f concat -safe 0 -i work/vl.txt \
  -c:v libx264 -crf 19 -pix_fmt yuv420p work/video.mp4
```

> concat demuxer 要求所有片段**编码参数完全一致**（分辨率/fps/pix_fmt/SAR）。
> 上面四个编码器都统一到了 `$V`，所以能直接 concat。
> 路径里有中文/空格时用绝对路径 + `-safe 0`。

### 拼音轨（每句 pad 到 `T_cNN`，让音画对齐）

```bash
ffmpeg -nostdin -y -v error \
  -i audio/c01.mp3 -i audio/c02.mp3 ... \
  -filter_complex "\
   [0:a]aresample=44100,volume=4dB,apad,atrim=0:$T_c01[a0];\
   [1:a]aresample=44100,volume=4dB,apad,atrim=0:$T_c02[a1];\
   ...
   [a0][a1]...concat=n=N:v=0:a=1[a]" -map "[a]" work/voice.m4a
```

`apad` + `atrim=0:$T_cNN` 是关键：把每句补静音补到 `配音时长+GAP`，
于是第 N 句音频的起点 == 第 N 拍视频的起点。**不加 apad 会逐拍累积漂移。**

### mux

```bash
ffmpeg -nostdin -y -v error -i work/video.mp4 -i work/voice.m4a \
  -c:v copy -c:a aac -b:a 192k -shortest <slug>-nosub.mp4
```

**整套已经写成可参数化脚本**：

```bash
lib/build-vertical.sh --project <dir> --shots shots.tsv --out <slug>-nosub.mp4
```

`shots.tsv` 每行：`clip<TAB>编码器<TAB>素材路径<TAB>起始秒`

```
c01	celeb	footage/ext/ai-deepseek.mp4	2
c02	card	html/beats/bench.webm	0
c05	patch	footage/rec/mingpan.mp4	2
c09	full	footage/rec/dialogue.webm	16
```

---

## 阶段 ⑥ 字幕 → `<slug>-v1.mp4`

见 `skills/subtitles/`。默认走 PIL overlay（不依赖 libass）：

```bash
python3 lib/gen-subs.py --project . --y 1400 --font-size 60
lib/burn-subs.sh <slug>-nosub.mp4 <slug>-v1.mp4
```

**时间轴必须和 build 用同一个 GAP**，否则字幕整体漂移。两边都从 `clips.json` + `ffprobe` 算，别手写时间。

某几拍的画面自带大字（数据卡、榜单）时，把这些 clip 加进 `--skip` 列表，别叠双层字。

---

## 阶段 ⑦ 封面 → `cover.png`

见 `skills/cover-thumbnail/`。竖版 1080×1440，巨字钩子 + 戏剧图 + 一行副标 + 品牌 tag。
**爆款风，不是学术风**——即使内容是讲论文的。

---

## 阶段 ⑧ 交付

见 `skills/delivery/`。

```bash
lib/package-delivery.sh --video <slug>-v3.mp4 --cover cover.png --caption caption.txt \
                        --out "<选题名>-v3-交付包.zip"
```

---

## 一条片子的完整 checklist

```
[ ] topic.md 写了钩子 / 为什么能火 / 落到什么功能
[ ] clips.json 字数对得上目标时长，无 "ta"，单句 ≤30 字
[ ] 镜头表列全，每句都有画面来源
[ ] 音色采样给人类挑过
[ ] audio/*.mp3 全部非空，verify-audio.sh 过
[ ] 逐拍 work/vNN.mp4 都存在且时长 == T_cNN
[ ] concat 后 video.mp4 时长 ≈ Σ(T_cNN)
[ ] mux 后有音轨，ffprobe 看得到 aac
[ ] 字幕条数 == 拆句数
[ ] verify-output.sh 全绿
[ ] 交付包打好，文件名唯一带版本
```

---

## 失败症状 → 修法

| 症状 | 修法 |
|---|---|
| concat 报 `Non-monotonous DTS` / 画面跳 | 逐拍编码参数不一致 → 检查每拍都过了 `$V` |
| 音画越到后面越不同步 | 音轨没 `apad`+`atrim` 到 `T_cNN` |
| 最后一拍被切掉 | `-shortest` 且音轨比视频长 → 检查最后一拍 `T` 是否算漏 GAP |
| 某一拍黑屏 | 素材比 `T_cNN` 短 → 换素材或 `setpts` 放慢 |
| 成片没声音 | 逐拍编码忘了 `-an`，或 mux 少了 `-map` |
| 字幕整体偏移固定值 | build 和 gen-subs 的 GAP 不一致 |
