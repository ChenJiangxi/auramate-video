---
name: product-demo
description: 产品录屏演示段——素材盘点→缺口→现录计划、Playwright 录制的三条硬约束、裁切放大的分辨率账、假浏览器壳包装、旧品牌打补丁。触发词：录屏、产品演示、Playwright、界面展示、功能展示、录制网页、裁切放大、浏览器壳。
---

# product-demo — 产品录屏演示段

产品片里，**真实界面 + 真实操作 + 真实输出**应占 ≥ 50% 时长。
纯字卡开场压到 ≤ 4s，品牌收尾 ≤ 3s。素材不够长就放慢，别加卡片凑。

---

## 一、先盘点，再决定录不录

**别一上来就开浏览器。** 顺序是：盘点已有 → 列缺口 → 只补缺口。

### 1. 盘点

```bash
for f in footage/rec/*.webm footage/rec/*.mp4 <历史素材目录>/*; do
  printf "%-44s %s\n" "$(basename "$f")" \
    "$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
        -show_entries format=duration -of csv=p=0 "$f" | tr '\n' ' ')"
done
```

盘出来的东西按**分辨率分三档**（这决定它还能不能用）：

| 档 | 说明 | 能干什么 |
|---|---|---|
| ≥ 1080×1920 | 直接可用 | 铺满 / 还能裁一点 |
| 720×1280 | 移动端满帧录屏 | 只能整屏升到 1080（1.5× 放大），**基本不能再裁** |
| ≤ 540×960 | 老素材 | 只能当次要画面，别做主角 |

### 2. 列缺口清单

对着镜头表逐句问：这一拍要展示什么功能？现有素材里有没有？够不够长？分辨率够不够裁？

```
c05 命盘特写      → 有 1080×1920 现成，够长          ✓
c06 缘分合盘分数  → 只有 720×1280，且要特写 → 缺，需现录
c07 报告下拉      → 没有                             → 缺，需现录
```

### 3. 只补缺口

一次录制脚本把缺口一起录掉，别一个功能开一次浏览器。

> **素材不够就去现录。** 「翻来覆去就那两个界面」是被专门挑过的问题——
> 产品功能要全面讲一遍，画面还要好看。

---

## 二、录制：三条硬约束

### 1. `recordVideo.size` 必须**完全等于** viewport

不等的话内容只填左上角，其余是黑边。这是最常见的翻车。

```js
const VP = { width: 720, height: 1280 };
const ctx = await browser.newContext({
  viewport: VP,
  deviceScaleFactor: 2,
  isMobile: true, hasTouch: true,
  userAgent: '<移动端 UA>',
  locale: 'zh-CN',
  recordVideo: { dir: workDir, size: VP },   // ← 必须和 viewport 一样
});
```

### 2. **录制分辨率要按「目标 × 打算裁的倍数」倒推**

这是最容易算错的一笔账。**裁切倍数和升采样倍数是相乘的**：

```
最终放大倍数 = 目标宽 ÷ (录制宽 ÷ 裁切倍数)
```

拿真实录屏量的（目标 1080×1920）：

| 录制宽 | 不裁 | 裁 1.5× | 裁 2.0× |
|---|---|---|---|
| 720 | **1.50×** | 2.25× ⚠ | 3.00× ✗ |
| 1080 | 1.00× | 1.50× | 2.00× ⚠ |
| 1620 | 0.67× | **1.00×** | 1.35× |
| 2160 | 0.50× | 0.75× | **1.00×** |

**结论：720×1280 的录屏，升到 1080×1920 就已经用掉 1.5× 了，再裁必糊。**
想做 1.5× 特写，录制宽至少 1620；想做 2× 特写，至少 2160。

窄布局（720）内容大、留白少但分辨率低；宽布局（1080+）清晰但主体小、留白多。

**布局归布局，像素归像素 —— 这两件事别混。** 这条踩了两次才弄明白：

```
第一次错：录 720 窄布局 → 布局对，但只有 720px
        → 升到 1080 已经 1.5×，再推就糊 → 不敢推 → 全片只剩 1.06-1.12× 的位移
        → 观众一眼看出「这不是推镜，是平移」

第二次错：把 viewport 调到 1080 想换像素 → **网站的响应式断点切到桌面布局**
        → 主视觉缩到角落、文字挤成一条、大片留白 → 竖版素材直接报废

对的做法：布局用窄 viewport（720），像素用 deviceScaleFactor（3）
        → 每帧 2160×3840，布局还是移动端
        → 推到 1.6× 时框宽还有 1350px，输出 1080 是**降采样**，一点不糊
```

`recordVideo` 的画面尺寸 = viewport 的 CSS 尺寸，**`deviceScaleFactor` 对它不起作用**。
要拿到高像素只能逐帧截图（`page.screenshot()` 认 dsf），再拼成视频：

```bash
node lib/rec-frames.js --url <URL> --out footage/rec/x.mp4 \
     --w 720 --h 1280 --dsf 3 --fps 12 --secs 14 --scroll 110 --scroll-every 9
```

代价是慢（每帧一次截图，14s 要 1–2 分钟）。换来的是推镜的前提。

**滚动速度要按页面调**：`--scroll 300 --scroll-every 4` 在长报告页上 3 秒就冲过头部了。
先用小值试，抽帧看每个时间窗停在哪儿。

### 3. SPA 冷加载 + 内层滚动

```js
try {
  await page.goto(url, { waitUntil: 'commit', timeout: 60000 });  // 不要 domcontentloaded
} catch (e) { console.log('goto slow', url); }
await page.waitForTimeout(5000);

// 很多 SPA 是内层容器滚动，window.scrollTo 无效
await page.mouse.move(VP.width / 2, VP.height / 2);
for (let i = 0; i < 16; i++) {
  await page.mouse.wheel(0, 340);
  await page.waitForTimeout(820);       // 慢滚才好看，也给懒加载时间
}
```

### 4. 需要「生成」的页面：先点按钮再轮询

```js
const startBtn = page.locator('button:has-text("开始"), button:has-text("生成")').first();
if (await startBtn.count().catch(() => 0)) {
  await startBtn.click({ timeout: 3000 }).catch(() => {});
  for (let k = 0; k < 30; k++) {                       // 最多等 60s
    await page.waitForTimeout(2000);
    const stillEntry = await page.locator('button:has-text("开始测试")').count().catch(() => 0);
    const len = await page.evaluate(() => document.body.innerText.length).catch(() => 0);
    if (!stillEntry && len > 900) break;
  }
  await page.waitForTimeout(3000);
}
```

### 5. 登录态复用

登录一次 → `storageState()` → 用它开一个**带 recordVideo 的新 context**，
录出来就没有登录过程。**必须 `context.close()`**（不是只 `page.close()`）视频才 flush。

模板：`lib/rec-page.js`。**已在真实站点上验过**这条链路（登录 → 复用 storageState →
录屏 → 输出 720×1280），密码只从 `--pw-env` 指定的环境变量读，不进 argv（argv 会泄露到 `ps`）：

```bash
DEMO_LOGIN_PW='<密码>' node lib/rec-page.js \
  --url "https://<站点>/app" --login-url "https://<站点>/login" \
  --email "<测试账号>" --pw-env DEMO_LOGIN_PW \
  --out footage/rec/app.webm --mobile --w 720 --h 1280 --scroll 8 --wait 6000
```

**所以产品素材不用人给** —— 给 URL + 测试账号，agent 自己录。

### 6. 光标：截图里**没有系统光标**

这条不做，录出来就是页面自己在动、输入框自己在填字、按钮自己变色。
观众看不到有人在操作，读起来像 bug 演示，不像产品演示。
`page.screenshot()` 和 `recordVideo` 都不含光标，必须自己往页面里画一个。

```bash
node lib/rec-frames.js --url <URL> --out footage/rec/x.mp4 \
     --w 720 --h 1280 --dsf 3 --fps 12 --secs 12 \
     --cursor touch --act shots/act.json
```

`--cursor touch` 是半透明圆点 + 按下水波纹（录的是移动端布局，观众预期是手指）；
`--cursor arrow` 是桌面箭头。给了 `--act` 会自动开光标。

**动作表**（`at` 是**视频时间**秒，不是墙上时间）：

```json
[
  { "at": 0.3, "do": "tap",   "to": "#birthday" },
  { "at": 1.0, "do": "type",  "text": "1995-08-11 07:30", "over": 1.1 },
  { "at": 2.4, "do": "tap",   "to": "button:has-text('排盘')" },
  { "at": 3.4, "do": "move",  "to": {"xp": 0.5, "yp": 0.42} },
  { "at": 4.4, "do": "wheel", "dy": 520, "over": 1.4 },
  { "at": 6.0, "do": "hide" }
]
```

`to` 三种写法：CSS 选择器（运行时才量，位置跟着页面走）/ `[x,y]` CSS 像素 /
`{xp,yp}` 视口比例。`tap` = 移过去再点，`move` 只移动，`hide`/`show` 收放光标。

四条踩出来的规矩：

1. **所有动画按帧推进，不许用 CSS animation / transition。**
   逐帧截图的墙上间隔不均匀（一帧 100–300ms 还会抖），按时间跑的动画在成片里
   会忽快忽慢。光标位置、按下形变、水波纹半径，每一帧都由外部显式摆好再截。
   跟音频驱动时间轴是同一条原则：**帧序号就是时钟**。
2. **落点在按下的那一刻重新量，不能用起步时量的坐标。**
   移动过程中页面很可能挪了 —— 惯性滚动没停、图片加载完撑高了、骨架屏换成真内容。
   挪几十像素最阴：画面上光标明明压在按钮上，实际擦着边点空，逐帧看都未必看得出来。
3. **手指的芯要留透。** 观众看产品片是来读界面的，不透明的圆点盖住按钮上的字就白录了。
   靠描边和投影撑存在感。
4. **目标在视口外要出声。** 元素被滚出去了，`boundingBox()` 给的是负数，
   点下去什么也不会发生。脚本会警告「先加一条 wheel 把它滚进来」。

移动是 smoothstep 缓动（和镜头运动同一条曲线）：起步收尾都软。
匀速移动看着像被拖着走，不像手。

`lib/rec-page.js` 也有 `--cursor`，但只能跟着真实鼠标事件走 ——
`recordVideo` 由浏览器按墙上时间录，插不进「每帧摆一次状态」。
**要动作表就用 `lib/rec-frames.js`。**

底下两个模块一般不用直接调，改光标长相或加动作类型时看它们：
`lib/cursor-overlay.js`（注入页面的自绘光标 + 水波纹，只暴露 `__cur.frame({x,y,press,ripple})`，
状态全由外部按帧给）、`lib/actor.js`（动作表 → 每帧该做什么的演员）。

回归测试：`tests/cursor-test.js`（查光标真画出来了、动作真作用到页面了、
水波纹是按帧推进的）。

---

## 三、裁切放大

原始录屏里 UI 通常是**居中的一列**，两侧大片留白。直接用会被评为
「录全屏感觉好小，一点都不惊艳」。

```bash
# 自动找内容区（只在真有黑边/留白时有用）
lib/zoom-crop.sh rec.webm work/v05.mp4 --dur 4.2 --ss 6 --auto

# 按倍数居中裁；--cy 把中心上移，主体常在上半部
lib/zoom-crop.sh rec.webm work/v05.mp4 --dur 4.2 --ss 6 --zoom 1.5 --cy 0.45

# 自己量好的精确框
lib/zoom-crop.sh rec.webm work/v05.mp4 --dur 4.2 --ss 6 --crop 960:540:480:300
```

### `--auto` 的适用边界（实测）

`--auto` 用 ffmpeg `cropdetect`。它找的是**黑边**，不是「重要元素」：

| 素材 | cropdetect 结果 | 说明 |
|---|---|---|
| 1080×1920 带上下暗场的成品素材 | `1032:844:24:372` | 有效，自动切掉了上方 372px 空场 |
| 720×1280 移动端满帧录屏 | `720:1280:0:0` | 原样返回——**本来就没黑边，没得裁** |

满帧录屏想放大只能 `--zoom`（按意图裁），别指望自动检测。脚本会明确提示这一点。

### agent 看不见画面，怎么量坐标

```bash
lib/zoom-crop.sh rec.webm out.mp4 --ss 8 --grid
# → out.grid.png：带青色网格（每 1/10 画幅一格）+ 左上角标注源画幅和格距
```

把这张图给人看，或自己按格数换算成 `--crop W:H:X:Y`。**这是唯一靠谱的量法**，
别猜坐标。

---

## 三·五、镜头运动 —— 产品演示片和「录屏截图」的分界线

**静态裁一块是不够的。** 全屏放录屏，手机上字就是看不清；裁死一块又呆板，
观众不知道该看哪儿。成熟的产品演示片靠**镜头把注意力带过去**：先给全貌，
再推到关键元素上，让那几个字自己变大。

```bash
lib/motion.sh rec.webm work/v05.mp4 --dur 4.2 --ss 6 \
    --move punch-in --to 620:900:50:260        # 从全屏缓推到报告正文
```

| `--move` | 干什么 | 什么时候用 |
|---|---|---|
| `locate` | **停 → 移 → 停** | **产品段首选**。先让观众看清整页，再走到目标，到位定住。<br>从头匀速插到尾会被看成「画面在滑」，停顿才是镜头感的来源 |
| `punch-in` | 全屏 → 目标框 | 匀速推近，节奏快的拍用 |
| `pull-out` | 目标框 → 全屏 | 「原来它在这儿」的揭示 |
| `pan` | 框 A → 框 B | 跟着长页面往下读、从一个模块滑到另一个 |
| `kenburns` | 极缓慢缩放漂移 | 静止画面加一点呼吸，别让它死在那儿 |
| `hold` | 不动 | 口径统一用，等价于 `zoom-crop` |

**缓动默认 `inout`**（两头慢中间快，像真人推镜）。`--ease linear` 是匀速，机械感重，
只在需要「机器在扫描」的观感时用。

### 怎么量目标框（agent 看不见画面）

```bash
lib/motion.sh rec.webm out.mp4 --ss 8 --grid
# → out.grid.png：带青色网格（每 1/10 画幅一格）
```

数格子得到 `W:H:X:Y`。**框的宽高比不用等于输出比例**，脚本会按输出比例补齐再推。

### 接进管线

`shots.tsv` 里编码器写 `motion`，**第 5 列原样是 motion.sh 的参数**：

```
c05	motion	footage/rec/report.webm	6	--move punch-in --to 620:900:50:260
c06	motion	footage/rec/report.webm	9	--move pan --from 720:1280:0:0 --to 640:900:40:340
```

### 别推过头

终点框越小，放大倍数越大。脚本会把**起点和终点的放大倍数都打出来**，
超过 2× 直接警告。推得越近越清楚是错觉 —— **超过源分辨率就是糊**，
根治还是回到第二节那张录制分辨率倒推表。

---

## 四、假浏览器壳（让录屏读起来像产品）

裸录屏像截图，不像产品。套一层 Mac 浏览器壳，立刻变成「这是一个真实存在的网站」。

```bash
# 1) 生成壳（每段的 URL 要跟着当前页面变，这正是加壳的价值）
/usr/bin/python3 lib/browser-chrome.py --url auramate.net --path " / play / fate-match" \
    --out assets/chrome-fate.png --w 1920 --h 120

# 2) 套上去
lib/wrap-chrome.sh rec.mp4 work/v05.mp4 --chrome assets/chrome-fate.png --dur 4.2 --ss 6
```

结构：

```
chrome[目标宽 × 壳高]     红黄绿灯 + 锁 + URL 药丸
      vstack
content[目标宽 × (目标高 - 壳高)]   裁切后 scale 上去
```

实测尺寸：横版 `1920×120` 壳 + `1920×960` 内容；竖版 `1080×100` 壳 + `1080×1820` 内容。
`wrap-chrome.sh` 会按壳图的宽高比自动算内容高度，不用手算。

**两个必须的保护**（都真炸过）：

- `-loop 1 -i chrome.png` **必须**配 `-t`，否则 ffmpeg 无限读那张图，编码永不结束
  （真实记录：单个 clip 卡到 67 分钟 CPU）。
- 源比这一拍短时，用 `--freeze`（`tpad=stop_mode=clone`）冻结末帧补足，
  不加就直接报错告诉你差几秒。

**风格化卡片（hook / CTA / 封面）不加壳**——它们是品牌美术，不是界面。

---

## 五、旧素材里的旧域名/旧品牌 → 打补丁

```bash
/usr/bin/python3 lib/make-brand-assets.py --url auramate.net \
    --brand "✦ auramate 灵伴" --pill-rgb 14,11,19 --out assets/
```

**底色必须从原视频里取真实 RGB**（抽一帧取药丸中心像素），差一点就有色块痕迹。
合成时 `overlay=<x>:<y>`，坐标每个素材单独量（用上面的 `--grid`）。

---

## 六、内容层面的规矩

- 产品功能要**全面讲一遍**且画面要好看，别翻来覆去就那两个界面。
- 功能页要**完整下拉录屏**展示全部内容，且**单独成块**，不跟其他素材混剪。
- 外部素材段顶部加品牌角标；产品段本身不用（界面里已经有品牌）。
- 界面里出现不想要的内容时，三种处理：
  1. 只用干净的时间窗（抽帧找出来）；
  2. 换个操作重录；
  3. **紧裁**，把不想要的区域裁到画外。
  **不要用大黑色 `drawbox` 遮**——看起来像半成品，被明确否过。

---

## 七、失败症状 → 修法

| 症状 | 根因 | 修法 |
|---|---|---|
| 录出来内容只在左上角 | `recordVideo.size` ≠ viewport | 两者必须完全相同 |
| `goto` 超时中断 | SPA 冷加载慢 | `waitUntil:'commit'` + `timeout:60000` + try/catch |
| 页面滚不动 | 内层容器滚动 | `mouse.move` + `mouse.wheel(0,340)` |
| 录到一半是空白 | 懒加载没等到 | 每次滚动后 `waitForTimeout(800+)` |
| 视频没生成 | 只 close 了 page | 必须 `context.close()` 才 flush |
| 成片里 UI 显得很小 | 没裁切放大 | `zoom-crop.sh --zoom 1.5 --cy 0.45` |
| 画面呆板像截图、观众不知道看哪 | 没有镜头运动 | `motion.sh --move punch-in --to <框>`，见三·五 |
| 裁完糊得没法看 | 录制分辨率不够，裁切倍数叠加了升采样 | 按第二节的表倒推录制分辨率，重录 |
| `--auto` 什么也没裁 | 满帧录屏本来没黑边 | 改用 `--zoom` 按意图裁 |
| 编码卡死不动 | `-loop 1` 没配 `-t` | `wrap-chrome.sh` 已内置，手写时别漏 |
| 这一拍比素材长 | 录得太短 | `--freeze` 冻结末帧，或重录 |
| 坐标全靠猜、裁错位置 | agent 看不见画面 | `--grid` 导网格样帧再量 |
