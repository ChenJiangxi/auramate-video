---
name: delivery
description: 把成片交付出去——唯一文件名铁律、zip 打包、故事板拼图、平台文案、faststart。踩过「对方永远看到第一版」的坑。触发词：交付、发给、打包、交付包、导出、故事板、caption、文案。
---

# delivery — 交付

## 一、唯一文件名（铁律）

**每一版都用带版本的唯一文件名，绝不复用同名。**

踩过的坑：一直用 `xuanxue-v1.mp4` 这个名字发了 7 版，对方每次打开看到的都是第一版
（前端按文件名缓存/去重），然后问「你还没给我发过」「把最新版发我」。卡了很久才定位到。

```
✅  财库-存不住钱-v3.mp4
❌  final.mp4 / output.mp4 / video-final-final.mp4
```

---

## 二、打包成 zip

很多聊天前端**对视频附件显示有问题**（图片附件一直正常）。
稳妥做法：**打 zip**，视频从 zip 里取。

```bash
lib/package-delivery.sh \
  --video 财库-存不住钱-v3.mp4 \
  --cover cover.png \
  --caption caption.txt \
  --out "财库-存不住钱-v3-交付包.zip"
```

包内结构：

```
财库-存不住钱-v3-交付包/
├── 财库-存不住钱-v3.mp4      成片
├── cover.png                封面
├── caption.txt              平台文案 + 话题标签
└── storyboard.jpg           故事板拼图（几帧拼一张）
```

---

## 三、故事板拼图（必给）

对方**一定能看到图片**，不一定能播视频。所以每次交付都附一张故事板大图，
让人一眼看到画面和节奏：

```bash
ffmpeg -i final.mp4 -vf "select='not(mod(n,90))',scale=360:-1,tile=4x3" \
       -frames:v 1 -q:v 3 storyboard.jpg
```

（每 90 帧取一张 = 30fps 下每 3 秒一张，4×3 拼成 12 格）

---

## 四、导出参数

```bash
-c:v libx264 -crf 19 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart
```

`-movflags +faststart` 把 moov 原子搬到文件头，网页/App 里才能边下边播。
漏了它对方点开会先转圈很久。`lib/verify-output.sh` 会检查这一项。

---

## 五、平台文案 `caption.txt`

```
<一句钩子，和视频第一句呼应但不重复>

<2–3 行展开，讲清价值>

#话题1 #话题2 #话题3
```

- 竖版平台话题标签 3–6 个，混合大词（#命理）和精准词（#缘分合盘）。
- 别把网址塞进正文首句——很多平台会限流；放结尾或简介。

---

## 六、交付前最后一遍

```bash
lib/verify-output.sh <成片.mp4> --expect-w 1080 --expect-h 1920 --fps 30 --min-dur 55 --max-dur 95
/usr/bin/python3 lib/check-compliance.py --project .    # 口播稿 + caption.txt 都过一遍
```

再人工确认（机器判断不了的）：

```
[ ] 第一句是钩子且具体
[ ] 每句台词都有对应画面
[ ] 数字全是真值
[ ] 网址 / 品牌名正确
[ ] 配音情绪对不对 —— 这条只能人类听
[ ] 合规三问：没承诺玄学结果 / 没替代医疗投资决策 / 拿掉产品后这是科普或情绪内容
```

合规 linter 只查词，查不了语义 —— **最终判断在人**。详见 `skills/compliance-redlines/`。

---

## 七、失败症状 → 修法

| 症状 | 修法 |
|---|---|
| 「怎么还没发给我」 | 同名文件被缓存 → 换唯一文件名 |
| 视频附件对方刷不出来 | 打 zip 发，视频从 zip 取 |
| 点开转圈很久才播 | 漏了 `-movflags +faststart` |
| 对方看不到本地路径的文件 | 本地路径对远端毫无意义，必须真的把文件传过去 |
| 交付后被问「画面是什么样」 | 附故事板拼图 |
