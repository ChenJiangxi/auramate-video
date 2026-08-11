---
name: ffmpeg-cookbook
description: ffmpeg 配方速查——竖版化、zoompan、变速、concat、音轨拼接、探测、抽帧、常见报错。做视频时随手查。触发词：ffmpeg、滤镜、concat、缩放、变速、抽帧、探测、编码参数、ffprobe。
---

# ffmpeg-cookbook — 配方速查

统一后缀（所有片段都过一遍，否则 concat 会炸）：

```bash
V="fps=30,setsar=1,format=yuv420p"
```

---

## 探测

```bash
# 时长
ffprobe -v error -show_entries format=duration -of csv=p=0 in.mp4
# 分辨率 + 编码 + 帧率
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,codec_name,r_frame_rate -of default=nw=1 in.mp4
# 有没有音轨
ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 in.mp4
# 音量峰值（判断是不是静音）
ffmpeg -v error -i in.mp3 -af volumedetect -f null - 2>&1 | grep max_volume
# 抽一帧看构图/量坐标
ffmpeg -v error -ss 5 -i in.mp4 -frames:v 1 /tmp/p.png
```

---

## 竖版化 1080×1920

```bash
# A. 已经是竖版 → 直接铺满
-vf "scale=1080:1920:flags=lanczos,$V"

# B. 低分辨率竖版 → 升采样必须补锐
-vf "scale=1080:1920:flags=lanczos,unsharp=7:7:0.9,$V"

# C. 横屏 → 模糊背景垫底 + 主体居中（保留真实混剪质感）
-vf "split=2[a][b];\
 [a]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=26:3,eq=brightness=-0.34:saturation=0.66[bg];\
 [b]scale=1080:820:force_original_aspect_ratio=decrease,unsharp=5:5:0.6[fg];\
 [bg][fg]overlay=(W-w)/2:440,$V"

# D. 横屏 → 硬裁中间（会切掉两侧，慎用）
-vf "scale=-2:1920,crop=1080:1920,$V"

# E. 视频居中 + 上下深色边（不模糊，更「素材感」）
-vf "scale=1040:-2,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:0x0a0a12,$V"
```

> **降采样出锐利文字，升采样出糊。** 源头就录 ≥ 目标分辨率。

---

## 静图 → 视频（缓推 zoompan）

```bash
ffmpeg -loop 1 -framerate 30 -t $T -i card.png -vf \
 "scale=2160:3840:flags=lanczos,\
  zoompan=z='min(zoom+0.0004,1.04)':d=1:s=1080x1920:fps=30,\
  fade=t=in:st=0:d=0.4,fade=t=out:st=$((T-0.4)):d=0.4,$V" \
 -c:v libx264 -crf 19 -pix_fmt yuv420p out.mp4
```

- 先放大到 2 倍（2160×3840）给 zoompan 留余量，输出再回 1080×1920，否则会抖。
- **`-loop 1` 必须配 `-t`**。不配的话 ffmpeg 无限读图，编码永不结束
  （真实踩过：单个 clip 卡 67 分钟）。

---

## 变速

```bash
# 视频：把 DUR_REC 秒的素材拉成 T 秒
PTS=$(awk -v t=$T -v d=$DUR_REC 'BEGIN{printf "%.4f", t/d}')
-vf "setpts=${PTS}*PTS"
# 音频（范围 0.5–2.0，超出串联）
-af "atempo=1.05"
```

1.4× 放慢读起来像「刻意的流畅」；**1.75× 是上限**，再慢就像慢动作了。

---

## concat

```bash
> list.txt; for f in v01 v02 v03; do echo "file '$PWD/work/$f.mp4'" >> list.txt; done
ffmpeg -f concat -safe 0 -i list.txt -c:v libx264 -crf 19 -pix_fmt yuv420p out.mp4
```

要求所有片段**编码参数完全一致**（分辨率 / fps / pix_fmt / SAR）。
路径有中文或空格时用绝对路径 + `-safe 0`。

---

## 转场（不动时间轴的做法）

`lib/build-vertical.sh` 已经内建，这里写清楚**为什么是这么算的**，
自己写别的合成脚本时照搬。

交叉溶解要两段素材重叠，天真做法是直接 xfade：

```bash
# ✗ 这么写总长会短掉 (n−1)×x
[v0][v1]xfade=transition=fade:duration=0.22:offset=<拍1长度>
```

短掉的后果不是「短一点」，是**每一句都往前串**，越到后面偏得越多，
最后一句被 mux 的 `-shortest` 直接切掉，而且不报错。

正确做法：把转场塞进**上一拍句末的 GAP 静音**里，让它**结束**在下一句开口的那一刻。

```
d_k        第 k 拍时长（= 配音时长 + GAP）
T_k        前 k 拍之和
x_k        进入第 k+1 拍的转场时长（要 ≤ GAP）

offset_k = T_k − x_k          转场结束正好是第 k+1 句开口
L_{k+1}  = d_{k+1} + x_k      入场那一拍要多渲 x_k 秒喂给转场
拼完长度 = offset_k + L_{k+1} = T_k + d_{k+1} = T_{k+1}   ← 和硬切一模一样
```

三个必须一起做到的点：

1. **多出来的 x 秒加在这一拍的前面，不能让内容整体提前。**
   起始秒有余量就回拉（`-ss` 减 x），起始秒是 0（卡片）就冻首帧顶上。
   否则「这句开口那一帧」会跟着转场时长变，开关转场会改变观众在关键时刻看到的东西。
2. **每一步用绝对时间 T_k 锚定，不要在上一步的结果上累加。**
   这样取帧的舍入误差不累积，只有最后一拍会差半帧。
3. **`settb` 不能省。** `concat` 滤镜输出时基是 1/1000000，`xfade` 要求两路时基一致，
   混用会直接报 `do not match the corresponding second input link xfade timebase`。

```bash
ffmpeg -i v01.mp4 -i v02.mp4 -i v03.mp4 -filter_complex "
[0:v]fps=30,settb=1/30,setpts=PTS-STARTPTS[s0];
[1:v]fps=30,settb=1/30,setpts=PTS-STARTPTS[s1];
[2:v]fps=30,settb=1/30,setpts=PTS-STARTPTS[s2];
[s0][s1]xfade=transition=fade:duration=0.22:offset=4.03,settb=1/30[j1];
[j1][s2]concat=n=2:v=1:a=0,settb=1/30[j2]" -map "[j2]" out.mp4
```

硬切边界用 `concat` 滤镜，别用 `duration=0` 的 xfade —— 它不报错，
但输出时长直接错（实测要 5.0s 出来 3.03s）。

**音频不用做交叉淡化**：转场整个落在静音的 GAP 里，两句话本来就不重叠。

转场时长 ≤ GAP（默认 GAP 0.25 / 转场 0.22）。超了就开始盖上一句的话尾。

---

## 音轨拼接（防漂移）

```bash
ffmpeg -i c01.mp3 -i c02.mp3 -filter_complex \
 "[0:a]aresample=44100,volume=4dB,apad,atrim=0:$T1[a0];\
  [1:a]aresample=44100,volume=4dB,apad,atrim=0:$T2[a1];\
  [a0][a1]concat=n=2:v=0:a=1[a]" -map "[a]" voice.m4a
```

`apad` + `atrim=0:$T` 把每句补静音到「配音时长 + GAP」，
于是第 N 句音频起点 == 第 N 拍视频起点。**不加会逐拍累积漂移。**

---

## mux + 导出

```bash
ffmpeg -i video.mp4 -i voice.m4a -c:v copy -c:a aac -b:a 192k -shortest \
       -movflags +faststart final.mp4
```

---

## 叠图 / 打补丁 / 角标

```bash
# 固定位置贴图（盖旧域名）
-filter_complex "[0:v][1:v]overlay=428:576"
# 全程顶部角标
-filter_complex "[0:v][1:v]overlay=0:24"
# 只在某段显示
-filter_complex "[0:v][1:v]overlay=0:0:enable='between(t,3.2,6.8)'"
```

---

## 故事板拼图

```bash
ffmpeg -i final.mp4 -vf "select='not(mod(n,90))',scale=360:-1,tile=4x3" -frames:v 1 -q:v 3 storyboard.jpg
```

---

## 报错速查

| 报错 / 现象 | 原因 | 修法 |
|---|---|---|
| `No such filter: 'ass'` / `'subtitles'` | 这台 ffmpeg 没 libass | 走 PNG overlay，见 `skills/subtitles/` |
| 编码永不结束 | `-loop 1` 没配 `-t` | 加 `-t` 或 `-shortest` |
| `Non-monotonous DTS` / concat 后画面跳 | 片段参数不一致 | 每片都过 `$V` 后重编码 |
| 成片没声音 | 逐拍忘了 `-an`，或 mux 漏 `-map` | 逐拍一律 `-an`，最后统一拼音轨 |
| 音画越到后面越偏 | 音轨没 `apad`+`atrim` | 见上面「音轨拼接」 |
| 输出比预期短 | `-shortest` + 某一路太短 | 检查各路时长 |
| 播放器要缓冲很久才开始 | moov 在文件尾 | 加 `-movflags +faststart` |
| 颜色发灰/发暗 | 少了 `format=yuv420p` 或色彩范围不匹配 | 统一 `format=yuv420p` |
| `Unknown decoder 'libdav1d'` | 源是 AV1 | 下载时 `-S "vcodec:h264"` |
| 中文路径找不到文件 | concat list 用了相对路径 | 用绝对路径 + `-safe 0` |
