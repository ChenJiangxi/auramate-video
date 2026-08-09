---
name: product-demo
description: 用 Playwright 录产品界面做演示段——viewport/recordVideo 约束、SPA 冷加载与内层滚动的坑、裁切放大、浏览器壳包装、旧域名打补丁。触发词：录屏、产品演示、Playwright、界面展示、功能展示、录制网页。
---

# product-demo — 产品录屏演示段

产品片里，**真实界面 + 真实操作 + 真实输出**应占 ≥ 50% 时长。
纯字卡开场压到 ≤ 4s，品牌收尾 ≤ 3s。素材不够长就放慢，别加卡片凑。

---

## 一、录制：三条硬约束

### 1. `recordVideo.size` 必须**完全等于** viewport

不等的话内容只填左上角，其余是黑边。这是最常见的翻车。

```js
const VP = { width: 720, height: 1280 };
const ctx = await browser.newContext({
  viewport: VP,
  deviceScaleFactor: 2,          // 2 倍像素，后期升采样才有料
  isMobile: true, hasTouch: true,
  userAgent: '<移动端 UA>',
  locale: 'zh-CN',
  recordVideo: { dir: workDir, size: VP },   // ← 必须和 viewport 一样
});
```

**分辨率取舍**：移动窄布局（720 宽）内容大、留白少，但只能低分辨率录；
宽布局（1080）清晰但主体变小、留白多。
折中：**720 布局录 → 后期 `scale=1080:1920:flags=lanczos` + `unsharp=5:5:0.6` 升 1.5×**。
能用现成 1080 素材的段就别依赖升采样。

### 2. SPA 冷加载会把 `goto` 拖超时

```js
try {
  await page.goto(url, { waitUntil: 'commit', timeout: 60000 });  // 不要 domcontentloaded
} catch (e) { console.log('goto slow', url); }
await page.waitForTimeout(5000);   // 等首屏真的渲染出来
```

`waitUntil:'domcontentloaded'` 在重前端应用上经常超时；`'commit'` 只等导航提交，配合固定
`waitForTimeout` 更稳。**外面一定要包 try/catch**，超时不该中断整次录制。

### 3. 很多 SPA 是**内层容器滚动**，`window.scrollTo` 无效

```js
await page.mouse.move(VP.width / 2, VP.height / 2);
for (let i = 0; i < 16; i++) {
  await page.mouse.wheel(0, 340);      // 一次滚一点
  await page.waitForTimeout(820);      // 慢滚才好看，也给懒加载时间
}
```

慢滚（340px / 820ms）比一次滚到底好看得多，成片里读得清。

### 4. 需要「生成」的页面要先点按钮再轮询

```js
const startBtn = page.locator('button:has-text("开始"), button:has-text("生成")').first();
if (await startBtn.count().catch(() => 0)) {
  await startBtn.click({ timeout: 3000 }).catch(() => {});
  for (let k = 0; k < 30; k++) {                       // 最多等 60s
    await page.waitForTimeout(2000);
    const stillEntry = await page.locator('button:has-text("开始测试")').count().catch(() => 0);
    const len = await page.evaluate(() => document.body.innerText.length).catch(() => 0);
    if (!stillEntry && len > 900) { console.log('ready @', k * 2, 's'); break; }
  }
  await page.waitForTimeout(3000);
}
```

### 5. 登录态复用

登录一次 → `storageState()` → 用它开一个**带 recordVideo 的新 context**。
这样录出来的视频里没有登录过程。

```js
const c1 = await browser.newContext({ ...VPOPTS });
await login(await c1.newPage());
const state = await c1.storageState(); await c1.close();
const c2 = await browser.newContext({ ...VPOPTS, storageState: state, recordVideo: { dir, size: VP } });
```

模板：`lib/rec-page.js`

---

## 二、后期：裁切放大是必须的

原始录屏里 UI 通常是**居中的一列**，两侧大片留白。直接用会被评为「录全屏感觉好小，一点都不惊艳」。

```bash
# 1.5× 常规放大
ffmpeg -i rec.webm -vf "crop=1280:720:320:Y,scale=1920:1080:flags=lanczos" out.mp4
# 2× 特写（对话框、评分圆环这类小元素）
ffmpeg -i rec.webm -vf "crop=960:540:480:Y,scale=1920:1080:flags=lanczos" out.mp4
```

`Y` 取值靠抽帧量：`ffmpeg -ss 5 -i rec.webm -frames:v 1 /tmp/p.png`，看图定位主元素中心。

**已经铺满画幅的素材（比如 1080×1920 直出的卡）不要再裁。**

---

## 三、浏览器壳包装（横版演示片）

裸录屏读起来像截图，不像产品。加一层假 Mac 浏览器壳：

```
chrome[1920×120]  ← 红黄绿灯 + 锁图标 + URL 药丸（写真实网址）
   vstack
content[1920×960] ← crop 后 scale 到这个尺寸
```

```bash
ffmpeg -loop 1 -i chrome.png -i content.mp4 -t $T \
  -filter_complex "[1:v]scale=1920:960[c];[0:v][c]vstack=inputs=2" -c:v libx264 -crf 19 out.mp4
```

> **`-loop 1` 必须配 `-t` 或 `-shortest`**，否则 ffmpeg 会无限读那张图，
> 编码永远不结束（真实踩过：单个 clip 卡到 67 分钟 CPU）。

每段的 URL 药丸要跟着当前页面变。风格化卡片（hook / CTA）不加壳——它们是品牌美术，不是界面。

---

## 四、旧素材里的旧域名/旧品牌 → PIL 打补丁

历史录屏里地址栏可能还是旧域名。做一张贴片盖上去：

```bash
/usr/bin/python3 lib/make-brand-assets.py --url auramate.net --out assets/
# → assets/url-patch.png（药丸底色精确匹配，无缝）
# → assets/brand-bug.png（顶部品牌角标）
```

**底色要用取色器从原视频取真实 RGB**，差一点就有色块痕迹。
合成时：

```bash
ffmpeg -i rec.mp4 -i assets/url-patch.png -filter_complex "[0:v][1:v]overlay=<x>:<y>" ...
```

坐标每个素材单独量，没有通用值。

---

## 五、内容层面的规矩

- 产品功能要**全面讲一遍**且画面要好看，别翻来覆去就那两个界面。素材不够就**去现录**。
- 功能页要**完整下拉录屏**展示全部内容，且**单独成块**，不跟其他素材混剪。
- 外部素材段顶部加品牌角标；产品段本身不用（界面里已经有品牌了）。
- 有些界面会输出你不想要的内容（比如某类术语），三种处理：
  1. 只用干净的时间窗（抽帧找出来）；
  2. 换个不会触发的操作重录；
  3. **紧裁**，把不想要的区域裁到画外。
  **不要用大黑色 `drawbox` 遮**——看起来像半成品，被明确否过。

---

## 六、失败症状 → 修法

| 症状 | 修法 |
|---|---|
| 录出来内容只在左上角 | `recordVideo.size` ≠ viewport |
| `goto` 超时中断 | `waitUntil:'commit'` + `timeout:60000` + try/catch |
| 页面滚不动 | 内层容器滚动 → `mouse.move` + `mouse.wheel` |
| 录到一半是空白 | 懒加载没等到 → 每次滚动后 `waitForTimeout(800+)` |
| 视频没生成 | 必须 `context.close()`（不是只 `page.close()`）才 flush 出 webm |
| 成片里 UI 显得很小 | 后期没裁切放大 |
| 编码卡死不动 | `-loop 1` 没配 `-t` |
| 界面糊 | 升采样过头 → 提高 `deviceScaleFactor` 或换现成高清素材 |
