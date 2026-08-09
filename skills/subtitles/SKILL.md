---
name: subtitles
description: 给成片加中文字幕——PIL PNG overlay 路线（不依赖 libass）与 ASS 路线的取舍、时间轴算法、位置/字号/描边规范、常见翻车。触发词：字幕、烧字幕、subtitle、ASS、SRT、字幕位置、字幕漏行。
---

# subtitles — 字幕

## 一、先决定走哪条路

```bash
ffmpeg -v error -filters | grep -E '^ .. (ass|subtitles) '
```

- **没输出 = 这台 ffmpeg 没编译 libass** → 必须走 **PNG overlay** 路线。
  很多 Homebrew 构建就是这样（`--enable-gpl` 但没 `--enable-libass`）。
  硬上 `-vf subtitles=x.ass` 会报 `No such filter: 'subtitles'`。
- 有输出 → ASS 路线可用，但 PNG 路线依然更可控（所见即所得、能精确控字距/描边）。

**默认走 PNG overlay。**

---

## 二、PNG overlay 路线（推荐）

```bash
/usr/bin/python3 lib/gen-subs.py --project . --y 1400 --font-size 60
lib/burn-subs.sh out-nosub.mp4 out-v1.mp4 --manifest subs/manifest.tsv
```

`gen-subs.py` 做两件事：算时间轴 + 渲染每行一张全画幅透明 PNG。
`burn-subs.sh` 把它们按 `enable='between(t,s,e)'` 串成一条 overlay 链，音轨 `-c:a copy` 原样保留。

> macOS 上必须用 **`/usr/bin/python3`**（系统 python 自带 Pillow）；
> homebrew 的 `python3` 通常没有 PIL。

### 时间轴算法（和 build 必须一致）

```
第 i 句起点 = Σ(前面每句配音时长 + GAP)      # GAP 默认 0.25，必须和 build-vertical.sh 相同
句内按标点切子句，每子句时长 ∝ 它的字数
```

两边都从 `clips.json` + `ffprobe` 现算，**绝不手写时间**。GAP 不一致 = 字幕整体漂移。

### 视觉规范（竖版 1080×1920）

| 项 | 值 | 理由 |
|---|---|---|
| 基线 Y | **1400** | 下三分之一。1660 太贴底，被否过 |
| 字号 | 60 | 手机上一眼能读 |
| 字色 | `#F5F1E9` | 纯白偏刺眼 |
| 描边 | 黑色 `stroke_width=7`，alpha 235 | 亮画面上也读得清 |
| 每行 | ≤ 15 字 | 超了断行 |
| 字体 | `/System/Library/Fonts/STHeiti Medium.ttc` | macOS 自带中文 |

### 钩子那句不要合并子句

默认会把短子句合并到 15 字以内（一行读起来更完整）。但**钩子句必须保住三拍节奏**：

```
默认合并：  「他三天没回你点开他的朋友圈」   ← 一整行，节奏没了
--no-merge：「他三天没回」「你点开他的朋友圈」「第十七次」  ← 三拍，一拍一个信息
```

钩子的力量来自「人物 → 动作 → 数字」三下砸，合成一行就废了。

```bash
/usr/bin/python3 lib/gen-subs.py --project . --no-merge     # 整片都不合并
```

更彻底的做法是**把钩子拆成多个 clip**（`c01a` / `c01b` / `c01c`），
一拍一个镜头 —— 这符合「一句 = 一个镜头」的主干规则，画面也能跟着切。

### 什么时候不叠字幕

某几拍的画面**自带大字**（数据榜卡、hook 大字卡）时，叠字幕会变双层。
把这些 clip 名传给 `--skip`：

```bash
/usr/bin/python3 lib/gen-subs.py --project . --skip c02,c03,c04
```

注意 `--skip` 的拍**仍然占时间轴**（它只是不渲染 PNG），所以后面的字幕不会漂。

---

## 三、ASS 路线

```bash
/usr/bin/python3 lib/gen-subs.py --project . --emit-ass
ffmpeg -i in.mp4 -vf "ass=subs/subs.ass" -c:a copy out.mp4
```

**必须在 `[Script Info]` 写 `PlayResX: 1080` / `PlayResY: 1920`。**
不写的话 libass 默认 `PlayResY=288`，所有 FontSize / MarginV 被隐式缩小约 6.7 倍，
结果是字幕小到看不见或者跑到画外——这是最容易踩的一个坑。

Alignment：`2` = 底部居中（MarginV 从底算）；`8` = 顶部居中（MarginV 从顶算）。
竖版下三分之一 → Alignment 2 + `MarginV = 1920 - 1400 = 520`。

---

## 四、硬规矩

1. **字幕必须 1:1 跟音频每一句，不许漏行。** 漏行会被当场抓出来。
   自检：字幕条数 == 所有非 skip 句子的拆分行数之和。
2. **位置在下三分之一**，不要贴底。
3. 结尾带链接/URL 的那一拍，字幕再抬高一些，别压住 URL。
4. 说的文本可以和屏幕文本不同（`他` vs `TA`），但**意思必须一致**。

---

## 五、失败症状 → 修法

| 症状 | 修法 |
|---|---|
| `No such filter: 'ass'` / `'subtitles'` | 这台 ffmpeg 没 libass → 走 PNG overlay |
| 字幕小到看不见 / 跑出画面 | ASS 缺 `PlayResX/Y` |
| 字幕整体提前或滞后固定值 | build 和 gen-subs 的 GAP 不一致 |
| 字幕越到后面越不同步 | 时间轴用了估算而不是 `ffprobe` 实测时长 |
| 少了几句 | `--skip` 写多了，或 `clips.json` 里那句 text 为空 |
| 画面出现双层字 | 该拍画面自带大字，应加进 `--skip` |
| overlay 链报错 / 极慢 | 字幕行数太多（>200），考虑合并短句或改用 ASS |
| 烧完没声音 | `burn-subs.sh` 里 `-map 0:a?` 被漏掉 |
