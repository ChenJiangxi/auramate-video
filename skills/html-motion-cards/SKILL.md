---
name: html-motion-cards
description: 用 HTML/CSS 渲染动效卡——hook 大字卡、数据卡、榜单卡的做法与边界（什么时候允许用卡、什么时候禁止）。触发词：动效卡、字卡、大字卡、数据卡、榜单、HTML 渲染、hook 卡。
---

# html-motion-cards — HTML 动效卡

## 一、先看边界（这条被专门澄清过，别搞混）

| 用途 | 允许？ |
|---|---|
| **标题 / 钩子 / 问句大字卡**（「你，偷偷合过盘吗？」砸屏） | ✅ 允许，情感/共鸣题甚至是主动要的 |
| **封面海报** | ✅ 允许（封面不算「素材」） |
| **数据卡 / 榜单卡**（数字来自真实实测） | ✅ 允许 |
| **假装成内容画面 / 证据 / B-roll 的卡** | ❌ 禁止 |
| **整片都是卡** | ❌ 禁止，被评为「太做、不真实」 |

判断方法一句话：**卡是「标题」→ 可以；卡假装是「画面」→ 不行。**

---

## 二、渲染流程

HTML → Playwright 录屏 / 截图 → mp4 或 png。

```bash
node lib/render-card.js --html html/cards/hook.html --out html/beats/hook.webm \
     --w 1080 --h 1920 --duration 4
```

要点：

- viewport 就是目标画幅（1080×1920），`deviceScaleFactor: 2`，`recordVideo.size` 必须相同。
- 动画建议 **3–5s 内跑完**，多余时长后期 trim 掉不影响观感。
- 静态卡直接截图成 PNG 更省事，但 **`-loop 1` 读 PNG 必须配 `-t`**。

---

## 三、写卡的规矩

1. **数字必须是真值。** 榜单/准确率/统计数字只能用委托方真跑出来的数据。
   自己画图可以，自己编数字绝不。数据来源写进 HTML 注释里，方便复核。
2. **一张卡只讲一件事。** 大字 ≤ 12 字，副标 ≤ 20 字。
3. **卡自带大字的那一拍要加进字幕 `--skip`**，否则双层字。
4. 竖版安全区：上下各留 ≥ 180px，主体在中间，别被平台 UI 压住。
5. 配色跟片子整体一致，别一张卡一个风格。

---

## 四、动画

CSS `animation-delay` 链在改时间时会牵一发动全身。更好的做法是用时间线库
（GSAP 一类）：改一拍不用重算下游所有 delay。缓动上 `power3` / `expo` / `back`
比默认 `ease-out` 更适合大字砸屏。

**把时间写在 HTML 的 data 属性上**，而不是写死在 build 脚本的数组里：

```html
<div class="beat" data-start="0" data-duration="4" data-src="01-hook.html"></div>
```

再用一个小脚本读 data 属性生成 ffmpeg concat 清单和字幕时间戳 —— 这样
「HTML / build 脚本 / 字幕」三处时间不会各自漂移（这类漂移踩过很多次）。

---

## 五、失败症状 → 修法

| 症状 | 修法 |
|---|---|
| 渲染出来只占左上角 | `recordVideo.size` ≠ viewport |
| 字体没生效 | 用本机装了的字体，或把字体 base64 内嵌进 HTML |
| 动画录到一半 | 录制时长 < 动画时长；或截图截太早 |
| ffmpeg 卡死 | `-loop 1` 读 PNG 没配 `-t` |
| 画面出现双层字 | 该拍要加进 `gen-subs.py --skip` |
| 卡看着很「假」 | 就是卡太多了 → 换真实素材，见 `skills/real-clip-mashup/` |
