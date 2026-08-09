---
name: real-clip-mashup
description: 用 yt-dlp 扒真实视频切片做混剪——搜素材、下载防坑、横屏转竖版、水印取舍、版权与主题匹配。真人切片比自制动画卡可信得多。触发词：混剪、切片、素材、yt-dlp、扒素材、真实画面、名人素材、B-roll。
---

# real-clip-mashup — 真人切片混剪

## 为什么

被反复强调过 ≥3 次：**不要全用 HTML 动画卡**。全卡片的版本会被评为「太做、不真实」。
真人切片带原声、带原水印、带原字幕——那种粗糙感恰恰是可信度的来源。

名人/热点选题就扒**那个人本人**的画面；知识选题就扒对应的纪录片/实拍。

---

## 一、搜 + 下

```bash
# 搜候选（不下载，先看标题/时长/分辨率）
yt-dlp "ytsearch8:关键词" --print "%(id)s %(duration)s %(resolution)s %(title)s" --no-warnings

# 下一条（强制 h264，避免 AV1 解码在 ffmpeg 侧报错）
yt-dlp -S "vcodec:h264" -f "bv*+ba/b" -o "footage/ext/%(id)s.%(ext)s" "<url>"
```

**站点特例**：某些站（如 bilibili）直连会返回 412，要伪装：

```bash
yt-dlp --user-agent "Mozilla/5.0" \
       --add-header "Referer:https://www.bilibili.com/" \
       -o "footage/ext/%(id)s.%(ext)s" "<url>"
```

**免费 stock 素材要抽帧检查水印**——很多带 "SLOW VIDEO" / "CLICK TO DOWNLOAD" 的巨大浮水印，
下之前先看一帧：

```bash
ffmpeg -v error -ss 3 -i src.mp4 -frames:v 1 /tmp/probe.png    # 然后看这张图
```

干净来源的经验：YouTube 上标 "no copyright" 的实拍片段通常可用。

---

## 二、选片段（比下载更重要）

1. `ffmpeg -ss N -i src.mp4 -frames:v 1 /tmp/p.png` 每隔几秒抽一帧，挑出**主体清晰、构图居中**的窗口。
2. 记下起始秒，写进 `shots.tsv` 第 4 列。
3. **片段必须 ≥ 对应配音时长**，不然那一拍会黑屏或定格。

**主题必须精准匹配台词**，不是气氛相近就行：

- 讲「现代财运 / 存不住钱」→ 数钞票、钞票下落（下落正好演「财来财去」）
- ❌ 古钱币 —— 那是古董收藏，不搭现代财运。这条被专门挑过。

---

## 三、横屏 → 竖版（模糊背景垫底 + 主体等比居中）

这是保留「真实混剪质感」的标准做法：源水印、源字幕都留着，不裁掉。

```bash
ffmpeg -nostdin -y -ss <起始秒> -t <时长> -i src.mp4 -vf \
 "split=2[a][b];\
  [a]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=26:3,eq=brightness=-0.34:saturation=0.66[bg];\
  [b]scale=1080:820:force_original_aspect_ratio=decrease,unsharp=5:5:0.6[fg];\
  [bg][fg]overlay=(W-w)/2:440,fps=30,setsar=1,format=yuv420p" \
 -an -c:v libx264 -crf 19 -pix_fmt yuv420p out.mp4
```

参数含义：

- `boxblur=26:3` + `brightness=-0.34` + `saturation=0.66` —— 背景要**足够暗、足够糊**，
  不然会跟前景抢注意力。
- 前景高度 `820`（≈ 画幅 43%），落在 `y=440`（≈ 23%）—— 主体在上三分之二，
  下面留给字幕（Y≈1400）。
- `unsharp=5:5:0.6` —— 补回缩放损失的锐度。

`lib/build-vertical.sh` 的 `celeb` 编码器就是这套，`shots.tsv` 里写：

```
c01	celeb	footage/ext/<id>.mp4	12
```

---

## 四、混剪的结构

**别整片都是切片**，也别整片都是卡。有效配比：

```
真人切片（主）+ 少量 hook/数据卡 + 产品录屏（如果是产品片，≥50% 时长）
```

外部素材画面**顶部要加品牌角标**，全程 overlay（`lib/make-brand-assets.py` 生成）。

找来的外网切片要**带原声 + 中文字幕解释**，别只放画面让观众猜。

---

## 五、失败症状 → 修法

| 症状 | 修法 |
|---|---|
| `Unknown decoder 'libdav1d'` / AV1 解码失败 | 下载时加 `-S "vcodec:h264"` |
| 下载 412 / 403 | 加 `--user-agent` + `--add-header "Referer:<站点首页>"` |
| 画面里有巨大 stock 水印 | 下之前抽帧检查；换 "no copyright" 来源 |
| 竖版化后主体被裁掉头 | 前景 `scale` 用 `force_original_aspect_ratio=decrease` 而不是 `increase` |
| 背景太抢眼 | 加大 `boxblur`、压 `brightness`/`saturation` |
| 那一拍定格/黑屏 | 素材比 `T_cNN` 短 → 换片段或 `setpts` 放慢 |
| 切片糊 | 源就是低分辨率 → 换源；不得已加 `unsharp=5:5:0.6` |
