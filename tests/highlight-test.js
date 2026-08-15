#!/usr/bin/env node
// highlight-test.js — 验强调层：暗场 / 高亮框 / 记号笔 / 标注气泡。被 tests/validate.sh 调用。
//
// 查的是六件真会坏的事:
//   ① 暗场真的只留一块亮 —— 别处变暗了、洞里没变暗
//   ② 高亮框只圈这一块 —— 不许顺手把别处也压暗（那是 spot 的活）
//   ③ 记号笔只盖文字下半截 —— 盖满了字就糊，这一拍白录
//   ④ 标注气泡贴在元素旁边，不是飘在画面中间
//   ⑤ 框跟着目标走 —— 页面滚了框还钉在原地，旁白说「看这里」就指错了
//   ⑥ 全都按**帧**推进 —— 用 CSS 动画的话，逐帧截图会把它拍成忽快忽慢
//   外加两条边界：目标滚出视口要出声（不能整屏全黑）、--no-cursor 只收手指不收强调
//
// 输出 "✓ …" / "✗ …"，退出码 0/1。
'use strict';
const path = require('path');
const { installCursor } = require(path.join(__dirname, '..', 'lib', 'cursor-overlay'));
const { Actor } = require(path.join(__dirname, '..', 'lib', 'actor'));
const { diff, luma } = require(path.join(__dirname, '_pngdiff'));

let chromium;
try { ({ chromium } = require('playwright')); }
catch { console.log('SKIP 没装 playwright'); process.exit(0); }

const FIX = 'file://' + path.join(__dirname, 'fixtures', 'page', 'index.html');
const W = 720, H = 1280, FPS = 12;
let bad = 0;
const ok = (m) => console.log(`  ✓ ${m}`);
const no = (m) => { console.log(`  ✗ ${m}`); bad++; };

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({
    viewport: { width: W, height: H }, deviceScaleFactor: 1,
    isMobile: true, hasTouch: true, locale: 'zh-CN',
  });
  await installCursor(ctx, { kind: 'touch', size: 46 });
  const page = await ctx.newPage();
  await page.goto(FIX, { waitUntil: 'domcontentloaded' });

  const rectOf = (sel) => page.evaluate((s) => {
    const r = document.querySelector(s).getBoundingClientRect();
    return { x: r.x, y: r.y, w: r.width, h: r.height };
  }, sel);
  const reset = async () => {
    await page.evaluate(() => window.scrollTo(0, 0));
    await page.waitForTimeout(300);
    await page.evaluate(() => window.__cur.frame({ fx: [], visible: false, x: -999 }));
  };
  // 每个用例都换一个新演员：强调是有状态的，串着用测出来的是上一条的残留
  const run = async (acts, frames, opts) => {
    const a = new Actor(page, acts, { fps: FPS, w: W, h: H, log: (m) => LOG.push(m), ...(opts || {}) });
    for (let i = 0; i < frames; i++) await a.tick(i);
    return a;
  };
  let LOG = [];

  await reset();
  const base = await page.screenshot();
  const grid = await rectOf('#grid');
  const go = await rectOf('#go');
  const h1 = await rectOf('h1');
  const FAR = { x: 20, y: h1.y - 6, w: 300, h: h1.h + 12 };   // 离 #grid / #go 都远的一块

  // ---------- ① 暗场：别处暗下去，洞里不动 ----------
  await run([{ at: 0, do: 'spot', to: '#grid', over: 0, hold: 9 }], 2);
  const shotSpot = await page.screenshot();
  const inBefore = luma(base, grid), inAfter = luma(shotSpot, grid);
  const outBefore = luma(base, FAR), outAfter = luma(shotSpot, FAR);
  outBefore - outAfter > 3 ? ok(`暗场把别处压暗了（亮度 ${outBefore.toFixed(1)} → ${outAfter.toFixed(1)}）`)
                           : no(`暗场没压暗别处（${outBefore.toFixed(1)} → ${outAfter.toFixed(1)}）`);
  Math.abs(inBefore - inAfter) < 2 ? ok(`洞里没被压暗（${inBefore.toFixed(1)} → ${inAfter.toFixed(1)}）`)
                                   : no(`洞里也被压暗了（${inBefore.toFixed(1)} → ${inAfter.toFixed(1)}）`);

  // 同一帧号重画必须是同一张 —— 有 CSS 动画就会随墙上时间飘
  await page.waitForTimeout(700);
  const shotSpotLater = await page.screenshot();
  const drift = diff(shotSpot, shotSpotLater, { x: 0, y: 0, w: W, h: H });
  drift < 0.4 ? ok('暗场不随墙上时间漂（没有 CSS 动画混进来）')
              : no(`暗场漂了 ${drift.toFixed(2)} —— 有按时间跑的动画`);

  // ---------- ⑤ 页面滚了，洞要跟着目标走 ----------
  // 滚过之后同一块画面里的**内容**也变了，所以得拿同一滚动位置的裸底来比。
  // 拿滚动前的底比，量到的是内容变化，不是强调有没有跟上（第一版就栽在这）。
  const a5 = new Actor(page, [{ at: 0, do: 'spot', to: '#grid', over: 0, hold: 9 }],
    { fps: FPS, w: W, h: H, log: () => {} });
  await a5.tick(0);
  await page.evaluate(() => window.scrollTo(0, 200));
  await page.waitForTimeout(250);
  const grid2 = await rectOf('#grid');
  await page.evaluate(() => window.__cur.frame({ fx: [] }));
  const baseS = await page.screenshot();
  await a5.tick(1);
  const shotMoved = await page.screenshot();
  grid2.y < grid.y - 100 ? ok(`目标随滚动上移了（y ${grid.y.toFixed(0)} → ${grid2.y.toFixed(0)}）`)
                         : no('目标没动，这条测不出跟随');
  const holeKept = Math.abs(luma(baseS, grid2) - luma(shotMoved, grid2));
  const dimmedFar = luma(baseS, FAR) - luma(shotMoved, FAR);
  holeKept < 2 && dimmedFar > 3
    ? ok(`洞跟着目标走了（新位置没被压暗 Δ${holeKept.toFixed(1)}，周围压暗 ${dimmedFar.toFixed(1)}）`)
    : no(`洞没跟上目标（新位置 Δ${holeKept.toFixed(1)}，周围压暗 ${dimmedFar.toFixed(1)}）`);

  // ---------- ⑧ 目标滚出视口：要出声，且不许整屏全黑 ----------
  // 滚到底，h1 就整个在视口上面了。fixture 只比视口高 342px，写死一个大数没用。
  LOG = [];
  await page.evaluate(() => window.scrollTo(0, 99999));
  await page.waitForTimeout(250);
  const h1off = await rectOf('h1');
  h1off.y + h1off.h < 0 ? ok(`滚到底后 h1 整个出了视口（y=${h1off.y.toFixed(0)}）`)
                        : no(`h1 还在视口里（y=${h1off.y.toFixed(0)}），这条测不了`);
  await page.evaluate(() => window.__cur.frame({ fx: [] }));
  const baseOff = await page.screenshot();
  await run([{ at: 0, do: 'spot', to: 'h1', over: 0, hold: 9 }], 2);
  const shotOff = await page.screenshot();
  LOG.some((m) => m.includes('视口外')) ? ok('目标滚出视口会警告')
                                        : no(`目标在视口外却没警告（日志 ${JSON.stringify(LOG)}）`);
  Math.abs(luma(baseOff, { x: 0, y: 200, w: W, h: 400 }) -
           luma(shotOff, { x: 0, y: 200, w: W, h: 400 })) < 2
    ? ok('目标不在视口里就整个不画（不会变成整屏全黑）')
    : no('目标在视口外，画面却被压暗了 —— 洞跑到屏幕外去了');

  await reset();

  // ---------- ② 高亮框：只圈这一块，不压暗别处 ----------
  await run([{ at: 0, do: 'ring', to: '#go', over: 0, hold: 9 }], 2);
  const shotRing = await page.screenshot();
  const edge = { x: go.x - 14, y: go.y - 14, w: go.w + 28, h: 16 };   // 按钮上边框那一条
  const dEdge = diff(base, shotRing, edge);
  const dFar = diff(base, shotRing, FAR);
  dEdge > 8 ? ok(`高亮框画出来了（边框处像素差 ${dEdge.toFixed(1)}）`)
            : no(`高亮框没画出来（差 ${dEdge.toFixed(1)}）`);
  dFar < 2 ? ok('高亮框不影响别处（不压暗）') : no(`高亮框污染了别处（差 ${dFar.toFixed(1)}）`);

  await reset();

  // ---------- ③ 记号笔：只盖下半截，字不糊 ----------
  await run([{ at: 0, do: 'mark', to: 'h1', over: 0, hold: 9 }], 2);
  const shotMark = await page.screenshot();
  const lower = { x: h1.x, y: h1.y + h1.h * 0.65, w: h1.w, h: h1.h * 0.35 };
  const upper = { x: h1.x, y: h1.y, w: h1.w, h: h1.h * 0.45 };
  const dLower = diff(base, shotMark, lower), dUpper = diff(base, shotMark, upper);
  dLower > 8 ? ok(`记号笔扫出来了（字底像素差 ${dLower.toFixed(1)}）`)
             : no(`记号笔没画出来（差 ${dLower.toFixed(1)}）`);
  dUpper < dLower * 0.35 ? ok(`字的上半截没被盖住（差 ${dUpper.toFixed(1)}）`)
                         : no(`记号笔糊住字了（上 ${dUpper.toFixed(1)} vs 下 ${dLower.toFixed(1)}）`);

  await reset();

  // ---------- ④ 标注气泡：贴在元素旁边 ----------
  await run([{ at: 0, do: 'label', to: '#grid', text: '真太阳时 19:30', over: 0, hold: 9 }], 2);
  const shotLabel = await page.screenshot();
  const above = { x: 40, y: grid.y - 62, w: W - 80, h: 50 };
  const dAbove = diff(base, shotLabel, above);
  const dInside = diff(base, shotLabel, { x: grid.x, y: grid.y + 10, w: grid.w, h: grid.h - 20 });
  dAbove > 6 ? ok(`标注气泡画在元素上方（像素差 ${dAbove.toFixed(1)}）`)
             : no(`气泡没出现在元素上方（差 ${dAbove.toFixed(1)}）`);
  dInside < 2 ? ok('气泡没盖住元素本身') : no(`气泡压在元素上了（差 ${dInside.toFixed(1)}）`);

  // ---------- 暗场必须排在框后面画（先 ring 后 spot 也不能把框压暗）----------
  await reset();
  const aOrder = new Actor(page, [
    { at: 0, do: 'ring', to: '#go', over: 0, hold: 9 },
    { at: 0, do: 'spot', to: '#grid', over: 0, hold: 9 },
  ], { fps: FPS, w: W, h: H, log: () => {} });
  await aOrder.tick(0);
  const order = await aOrder._tickFx(1);
  order[0] && order[0].kind === 'spot'
    ? ok('暗场排在最前面画（框不会被自己的暗场压暗）')
    : no(`画的顺序不对：${order.map((f) => f.kind).join(' → ')}`);

  // ---------- ⑥ hold 到了自己退场，clear 能提前收 ----------
  await reset();
  const a6 = new Actor(page, [
    { at: 0, do: 'ring', to: '#go', over: 0, hold: 9, id: 'r1' },
    { at: 0.2, do: 'clear', id: 'r1', out: 0 },
  ], { fps: FPS, w: W, h: H, log: () => {} });
  for (let i = 0; i < 8; i++) await a6.tick(i);
  const shotCleared = await page.screenshot();
  const dCleared = diff(base, shotCleared, edge);
  dCleared < 2 ? ok('clear 之后画面收干净了') : no(`clear 之后还有残留（差 ${dCleared.toFixed(1)}）`);
  a6.fx.length === 0 ? ok('退场走完的强调从队列里丢掉了') : no(`队列里还留着 ${a6.fx.length} 条`);

  // hold 到点自己退场
  await reset();
  const a7 = new Actor(page, [{ at: 0, do: 'ring', to: '#go', over: 0, hold: 0.25, out: 0 }],
    { fps: FPS, w: W, h: H, log: () => {} });
  for (let i = 0; i < 3; i++) await a7.tick(i);
  const midHold = a7.fx.length;
  for (let i = 3; i < 12; i++) await a7.tick(i);
  midHold === 1 && a7.fx.length === 0 ? ok('hold 到点自己退场')
                                      : no(`hold 没按时退场（中途 ${midHold} 条，最后 ${a7.fx.length} 条）`);

  // ---------- --no-cursor：手指收起来，强调照画 ----------
  await reset();
  // 手指落点要离 #go 远一点：高亮框带外发光，挨着量就分不清是手指还是框
  const FGX = 560, FGY = 900;
  await run([
    { at: 0, do: 'move', to: [FGX, FGY], over: 0 },
    { at: 0, do: 'ring', to: '#go', over: 0, hold: 9 },
  ], 3, { cursorVisible: false });
  const shotNoCur = await page.screenshot();
  const dFinger = diff(base, shotNoCur, { x: FGX - 40, y: FGY - 40, w: 80, h: 80 });
  const dRing2 = diff(base, shotNoCur, edge);
  dFinger < 2 ? ok('cursorVisible=false 时手指不画') : no(`手指还在（差 ${dFinger.toFixed(1)}）`);
  dRing2 > 8 ? ok('收了手指，强调照画（--no-cursor 只管手指）')
             : no(`收了手指连强调也没了（差 ${dRing2.toFixed(1)}）`);

  await browser.close();
  process.exit(bad ? 1 : 0);
})().catch((e) => { console.log(`  ✗ 崩了: ${e.message}`); process.exit(1); });
