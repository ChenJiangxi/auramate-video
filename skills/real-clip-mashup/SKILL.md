---
name: real-clip-mashup
description: 用 yt-dlp 扒真实视频切片做混剪——检索策略、下载防坑、落地体检（水印/编码/分辨率）、任意画幅转竖版的参数查表。真人切片比自制动画卡可信得多。触发词：混剪、切片、素材、yt-dlp、扒素材、真实画面、名人素材、B-roll、水印、竖版化。
---

# real-clip-mashup — 真人切片混剪

## 为什么

被反复强调过 ≥3 次：**不要全用 HTML 动画卡**。全卡片的版本会被评为「太做、不真实」。
真人切片带原声、带原水印、带原字幕——那种粗糙感恰恰是可信度的来源。

名人/热点选题就扒**那个人本人**的画面；知识选题就扒对应的纪录片/实拍。

工作流固定四步，**一步都不能跳**：

```
① 检索 → ② 体检（抽帧看！）→ ③ 挑起始点 → ④ 竖版化
   search      probe                看 contact 图       fit-vertical
```

---

## 一、检索

```bash
lib/fetch-clip.sh search "money falling no copyright" -n 8
```

输出 id / 时长 / 分辨率 / 标题，**不下载**。先看再下。

### 关键词怎么构造

| 目的 | 加什么词 |
|---|---|
| 找可用的空镜 | `no copyright` / `free stock` / `royalty free` |
| 找名人本人画面 | 人名 + 场合（`采访` / `演讲` / `纪录片`） |
| 找纪录片段 | 题材 + `纪录片` / `documentary` |
| 避开解说二创 | 加 `原片` / `raw` / `full` |

**名人题材只用本人真实画面**，来源要能说清是哪个场合、哪一年。

---

## 二、下载

```bash
lib/fetch-clip.sh get <url> -o footage/ext/celeb-x.mp4
lib/fetch-clip.sh get <url> -o footage/ext/x.mp4 --site bilibili   # 412/403 时
lib/fetch-clip.sh get <url> -o footage/ext/x.mp4 --codec any       # 只有 av1 源时
```

默认 `-S "vcodec:h264,res:1080"`——**强制 h264**，因为 AV1 / HEVC 在部分 ffmpeg 构建上解不了。

> **现实是这条经常被忘。** 量了一个真实素材库的 35 条外部素材：
> **h264 × 30 / av1 × 4 / hevc × 1**。也就是说有 5 条是在没加 `-S` 的情况下下的。
> 本机 ffmpeg 带 libdav1d 能解，换台机器就炸。**下的时候加，比事后转码省事。**

某些站直连返回 412/403，`--site` 预设会带上 UA + Referer：

| 站点 | 需要 |
|---|---|
| bilibili | `--user-agent` + `Referer: https://www.bilibili.com/` |
| douyin | 同上，Referer 换 douyin |

---

## 三、体检 —— 这一步最容易被跳过，也最容易翻车

```bash
lib/fetch-clip.sh probe footage/ext/x.mp4 --need 6      # --need = 这一拍要几秒
```

打印画幅 / 编码 / 时长 / **转竖版要放大几倍**，并抽 9 帧拼成一张 `<name>-contact.jpg`。

### 必须打开那张图看一眼

**真实案例**：一条 1280×720、标题写着「数钞票」的免费素材，ffprobe 看一切正常
（h264、55s、0.84× 降采样，参数完美）。抽帧一看，9 格里：

```
ROYALTY FREE STOCK FOOTAGES │ TO DOWNLOAD THIS FOOTAGE │ CLICK TO DOWNLOAD
DOWNLOAD IT BY THE LINK BELOW VIDEO │ 热气球 │ 火焰 │ 机场 │ ...
```

**只有 1 格是真的数钞票画面，而且带着水印。** 其余全是这个频道的下载广告和无关镜头。
不抽帧就会把「CLICK TO DOWNLOAD」剪进片子里。

常见的免费素材水印：`SLOW VIDEO` / `CLICK TO DOWNLOAD` / `STOCK` / 站点 logo 平铺。
**ffprobe 一个都看不出来。**

### 干净来源的经验

- YouTube 上标 `no copyright` 的**实拍**片段通常可用（合成的「免费素材合集」频道最容易带广告）。
- 纪录片正片、新闻档案、名人采访原片——带原字幕原台标反而是加分项（真实感）。

---

## 四、挑起始点

看 contact 图选**主体清晰、构图居中**的窗口，记下秒数：

```bash
ffmpeg -v error -ss 12 -i src.mp4 -frames:v 1 /tmp/p.png    # 精确到某一秒再确认
```

**片段必须 ≥ 这一拍的配音时长**，不然会黑屏或定格。`fit-vertical.sh` 会替你拦住。

**主题必须精准匹配台词**，不是气氛相近就行：

- 讲「现代财运 / 存不住钱」→ 数钞票、钞票下落（下落正好演「财来财去」）
- ❌ 古钱币 —— 那是古董收藏，不搭现代财运。这条被专门挑过。

---

## 五、竖版化

```bash
lib/fit-vertical.sh footage/ext/x.mp4 work/v03.mp4 --dur 4.2 --ss 12
```

自动按源画幅选模式，输出 1080×1920 / 30fps / 无音轨（音轨最后统一拼）。

### 三种模式

| mode | 做法 | 什么时候用 |
|---|---|---|
| **blur** | 模糊背景垫底 + 主体等比居中 | 横屏 / 方形源。**默认，也是保留「真实混剪质感」的标准做法**（源水印、源字幕都留着） |
| **fill** | 等比放大铺满后裁切 | 源本来就接近 9:16，且放大不超过阈值 |
| **pad** | 主体居中 + 上下深色边 | 想要更强的「素材感」，代价是上下大片死区 |

`auto` 的判定：AR < 0.85（竖版源）且铺满所需放大 ≤ 2.5× → `fill`；否则一律 `blur`。

### 放大倍数阶梯 —— 决定糊不糊

`blur` 模式前景默认铺满 1080 宽，所以**放大倍数 = 1080 ÷ 源宽**。
下面每一档都是从真实素材库里量出来的：

| 源画幅 | 前景放大 | 判定 | 库里的例子 |
|---|---|---|---|
| 1920×1080 | **0.56×** | 降采样，最锐 | 名人 FHD 素材、钞票下落 |
| 1280×720 | **0.84×** | 降采样，最锐 | 纪录片、五行动画 |
| 960×720 | **1.12×** | 可用 | 暗恋主题实拍 |
| 640×360 / 640×480 | **1.69×** | 可用，已加 `unsharp` | 模型输出录屏、里根白宫档案 |
| 360×640（竖版） | **2.00×** | 勉强 | 手机竖拍塔罗 |
| 480×360 / 480×852 | **2.25×** | 勉强，优先换源 | 老素材 |
| 448×336 | **2.41×** | 勉强，优先换源 | 早年低清切片 |
| — | **> 2.5×** | 别用 | 换源，或缩小前景让模糊背景占更多 |

`fit-vertical.sh` 会在 >1.8× 时提示、>2.5× 时警告，并自动加 `unsharp=5:5:0.6`。
**超过 2.5× 时它会自动缩小前景盒子**（`--max-upscale` 可调），宁可主体小一点也别糊。

### 前景摆在哪

```
前景视觉中心 = 画面 40% 高度处      → 主体在上三分之二
前景底边 ≤ 1340                     → 不压到字幕基线 1400
顶部至少留 60px
```

实测落点（`fit-vertical.sh` 自动算）：

```
16:9 源  → 前景 1080×606 @ y=465
4:3  源  → 前景 1080×810 @ y=363
9:16 源  → 前景  720×1280 @ y=60   （竖版源放不下就顶格）
```

### 手写 ffmpeg 的话

```bash
ffmpeg -nostdin -y -ss <起始秒> -t <时长> -i src.mp4 -vf \
 "split=2[a][b];\
  [a]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=26:3,eq=brightness=-0.34:saturation=0.66[bg];\
  [b]scale=1080:606:force_original_aspect_ratio=decrease,unsharp=5:5:0.6[fg];\
  [bg][fg]overlay=(W-w)/2:465,fps=30,setsar=1,format=yuv420p" \
 -an -c:v libx264 -crf 19 -pix_fmt yuv420p out.mp4
```

- `boxblur=26:3` + `brightness=-0.34` + `saturation=0.66` —— 背景要**足够暗、足够糊**，
  不然会跟前景抢注意力。
- `-an` 必须有：音轨最后统一拼（见 `skills/vertical-shortform/`）。

---

## 六、混剪的结构

**别整片都是切片**，也别整片都是卡：

```
真人切片（主）+ 少量 hook/数据卡 + 产品录屏（产品片要 ≥50% 时长）
```

- 外部素材画面**顶部加品牌角标**，全程 overlay（`lib/make-brand-assets.py` 生成）。
- 找来的外网切片要**带原声 + 中文字幕解释**，别只放画面让观众猜。
- 素材来源要写进交付文案的「数据源」栏，可核（见 `references/caption-template.md`）。

---

## 七、失败症状 → 修法

| 症状 | 根因 | 修法 |
|---|---|---|
| 片子里出现「CLICK TO DOWNLOAD」 | 没抽帧看就剪 | `fetch-clip.sh probe`，打开 contact 图 |
| `Unknown decoder` / AV1 解码失败 | 源是 av1/hevc | 下载时 `--codec h264`（默认就是） |
| 下载 412 / 403 | 缺 UA / Referer | `--site bilibili` / `--site douyin` |
| 竖版化后主体被裁掉头 | 用了 `fill` 模式硬裁 | 改 `blur`（`auto` 默认就会选 blur） |
| 画面糊 | 前景放大 > 2.5× | 换高分辨率源；或调小 `--max-upscale` 让前景小一点 |
| 背景太抢眼 | blur/压暗不够 | 加大 `boxblur`，压 `brightness` / `saturation` |
| 那一拍定格 / 黑屏 | 素材比这一拍短 | `fit-vertical.sh` 会直接报错并告诉你还差几秒 |
| 字幕压住人脸 | 前景底边越过 1340 | `fit-vertical.sh` 自动兜住；手写时检查 `overlay` 的 y |
| concat 报错 | 各拍参数不一致 | 全部走 `fit-vertical.sh`（统一 30fps / SAR / yuv420p） |
