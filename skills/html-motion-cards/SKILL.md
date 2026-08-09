---
name: html-motion-cards
description: HTML/CSS 动效卡——5 套可直接用的模板（钩子砸屏/问句共鸣/榜单/对比/品牌收尾）、公共设计系统、storyboard.json 驱动渲染并直接产出 shots.tsv。含卡片允许与禁止的边界。触发词：动效卡、字卡、大字卡、数据卡、榜单、HTML 渲染、hook 卡、storyboard、模板。
---

# html-motion-cards — HTML 动效卡

## 一、先看边界（这条被专门澄清过，别搞混）

| 用途 | 允许？ |
|---|---|
| **标题 / 钩子 / 问句大字卡** | ✅ 允许，情感/共鸣题甚至是主动要的 |
| **封面海报** | ✅ 允许（封面不算「素材」） |
| **数据卡 / 榜单卡**（数字来自真实实测） | ✅ 允许 |
| **假装成内容画面 / 证据 / B-roll 的卡** | ❌ 禁止 |
| **整片都是卡** | ❌ 禁止，被评为「太做、不真实」 |

一句话：**卡是「标题」→ 可以；卡假装是「画面」→ 不行。**
真实素材怎么找见 `skills/real-clip-mashup/`。

---

## 二、五套模板

都在 `skills/html-motion-cards/templates/`，1080×1920，`@import` 同目录的 `_base.css`。

| 模板 | 用途 | 关键字段 |
|---|---|---|
| `hook-slam` | 钩子砸屏。两行宋体大字 + 脚注 + 背景巨大问号 | `l1` `l2` `sub` `ghost` |
| `question` | 问句 / 共鸣。两行叙述 + 输入框 + 落点句 | `a` `b` `placeholder` `foot` |
| `bar-rank` | 榜单。横向条形图 + 两条参考线 + 结论 | `title` `sub` `rows[]` `guessAt` `passAt` `verdict` |
| `stat-compare` | A vs B 两个大数字 + 结论 | `leftValue` `rightValue` `verdict` |
| `cta-brand` | 收尾品牌卡 | `brand` `tagline` `url` |

### 设计系统（`_base.css`）

从真实交付过的几十张卡里抽出来的，改一个变量全片跟着变：

```css
--bg   #08070c        底色，三档（默认 / warm / cool）
--fg   #f2eee6        主文。不用纯白，纯白刺眼
--gold #f0b24a        知识/严肃/玄学（默认）
--pink #ff86b6        情感/共鸣
--red  #ff6b5c        警示/反差结论
--serif "Songti SC"   标题用宋体 = 分量感
--sans  "PingFang SC" 正文
```

**氛围三层，顺序不能反**：`.glow`（径向光晕 + blur）→ `.stars`（几个 radial-gradient 点）
→ `.vig`（暗角）。

**字号阶梯**（竖版实测可读）：`150 / 120 / 96 / 76 / 62 / 52 / 38 / 30`。
砸屏主句最多 6 字，副句 ≤ 8 字。

**动画**：`.slam`（scale 1.4→1，带回弹）配大字；`.up`（translateY 34px→0）配成串短句；
`.fade` 配脚注。延时用 `.d1`–`.d6`（0.2s 起，每级 +0.3s）——改一拍不用重算下游全部。
**动画总时长 ≤ 3s**，卡渲 3–5s 就够。

---

## 三、storyboard.json 驱动

不要手抄 HTML 改文字。写一份 `storyboard.json`，一条命令填模板 + 渲染 + 产出 `shots.tsv`：

```json
{
  "accent": "gold",
  "beats": [
    {"clip":"c01","template":"hook-slam",
     "data":{"l1":"AI 算命","l2":"卷成这样了？","sub":"八字 · 合盘 · 人生K线","ghost":"?"}},
    {"clip":"c04","template":"bar-rank","dur":6.5,
     "data":{"title":"全球最强 AI · 考<span class=\"hl\">中国命理</span>",
             "sub":"命理大赛真题 · 综合准确率",
             "guessAt":"0.25","guessLabel":"瞎猜 25",
             "passAt":"0.60","passLabel":"及格 60",
             "verdict":"最高 40.3 ——","verdictHl":"全部不及格",
             "rows":[{"rank":1,"name":"Model-A","tag":"Reasoning","value":40.3,
                      "color":"linear-gradient(90deg,#7fd0e0,#6bbcd0)"}]}}
  ]
}
```

```bash
node lib/storyboard.js --project .              # 填模板 + 渲染 + 写 shots.tsv
node lib/storyboard.js --project . --no-render  # 只填模板和 shots.tsv（不需要浏览器）
lib/build-vertical.sh --project . --shots shots.tsv
```

### 时长从哪来（跟主管线同一套规则）

```
beat.dur  >  audio/<clip>.mp3 时长 + GAP  >  3.5s 兜底
```

**默认就是 audio-driven** —— 只要 `audio/cNN.mp3` 已经生成，卡的时长自动跟配音对齐，
不会和 `build-vertical.sh` 漂。

> 实测：playwright 录出来的 webm 会比 `dur` **多 0.6–0.9s**（浏览器启停帧）。
> 这是好事——卡永远够长，`build-vertical.sh` 用 `-t` 裁到精确时长。

### 模板语法

```html
{{key}}                                   标量
<!-- repeat:rows --> ... <!-- /repeat -->  数组，行内可用 {{rank}} {{name}} {{index}} {{delay}}
```

数组会自动派生 `rowsCount` / `rowsH`（行数 × 118px），模板里用它把参考线长度跟行数绑起来。
故意做得很小——**模板要能被人直接读懂和手改**，不引第三方模板引擎。

填好的 HTML 落在 `work/cards/<clip>.html`，**可以直接用浏览器打开调样式**，调好再渲染。

---

## 四、写卡的规矩

1. **数字必须是真值。** 榜单/准确率只能用真跑出来的数据。自己画图可以，自己编数字绝不。
   数据来源写进交付文案的「数据源」栏（见 `references/caption-template.md`）。
2. **一张卡只讲一件事。** 大字 ≤ 12 字，副标 ≤ 20 字。
3. **卡自带大字的那一拍要加进字幕 `--skip`**，否则双层字：
   `gen-subs.py --project . --skip c02,c03`
4. 竖版安全区：上下各留 ≥ 180px（`_base.css` 里有 `.safe`）。
5. 配色跟片子整体一致——改 `accent` 一个字段就行，别一张卡一个风格。

---

## 五、渲染的两条硬约束

- **`recordVideo.size` 必须 === viewport**，否则内容只填左上角。
- **必须 `context.close()`**（不是只 `page.close()`）才 flush 出 webm。

`storyboard.js` 都处理好了；自己写渲染脚本时别漏。

---

## 六、失败症状 → 修法

| 症状 | 根因 | 修法 |
|---|---|---|
| 渲染出来只占左上角 | `recordVideo.size` ≠ viewport | 两者必须完全相同 |
| 没生成 webm | 只 close 了 page | 必须 `context.close()` |
| **元素动画结束后跑位** | `.up` 的 `to{transform:none}` 把 `translateX(-50%)` 覆盖了 | 居中改用 `left/right` 定位，别用 transform（真踩过：框整体右移 410px） |
| 参考线拖到画面底部 | 高度写死 `bottom:250px`，行数少时不匹配 | 用 `{{rowsH}}` 让长度跟行数走 |
| 占位符没替换（页面上出现 `{{x}}`） | data 里少了字段 | `storyboard.js` 会 `!` 警告列出缺哪个 |
| 字体没生效 | 本机没装 | 换 `_base.css` 里的 `--serif` / `--sans`，或把字体 base64 内嵌 |
| 动画录到一半 | 渲染时长 < 动画时长 | 动画总时长压到 ≤3s，或调大 `dur` |
| 画面出现双层字 | 卡自带大字又叠了字幕 | 该拍加进 `gen-subs.py --skip` |
| ffmpeg 卡死 | `-loop 1` 读 PNG 没配 `-t` | 见 `skills/ffmpeg-cookbook/` |
| 卡看着很「假」 | 就是卡太多了 | 换真实素材，见 `skills/real-clip-mashup/` |
