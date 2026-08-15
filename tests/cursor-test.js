#!/usr/bin/env node
// cursor-test.js — 验光标叠加层 + 动作表演员。被 tests/validate.sh 调用。
//
// 查的是三件真会坏的事:
//   ① 光标画出来了吗（截图里那块像素真的变了）—— 画不出来就等于没做
//   ② 动作真的作用到页面了吗（聚焦/输入/点击/滚动）—— 光标看着在点、其实点空过
//   ③ 水波纹是按**帧**推进的吗 —— 用 CSS 动画的话，逐帧截图会把它拍成忽快忽慢
//
// 输出 "✓ …" / "✗ …"，退出码 0/1。
'use strict';
const path = require('path');
const { installCursor } = require(path.join(__dirname, '..', 'lib', 'cursor-overlay'));
const { Actor } = require(path.join(__dirname, '..', 'lib', 'actor'));

let chromium;
try { ({ chromium } = require('playwright')); }
catch { console.log('SKIP 没装 playwright'); process.exit(0); }

const FIX = 'file://' + path.join(__dirname, 'fixtures', 'page', 'index.html');
const W = 720, H = 1280, FPS = 12;
let bad = 0;
const ok = (m) => console.log(`  ✓ ${m}`);
const no = (m) => { console.log(`  ✗ ${m}`); bad++; };

// 两张 PNG 在某个矩形里的平均像素差（解码器和 highlight-test.js 共用）
const { diff } = require(path.join(__dirname, '_pngdiff'));

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({
    viewport: { width: W, height: H }, deviceScaleFactor: 1,
    isMobile: true, hasTouch: true, locale: 'zh-CN',
  });
  await installCursor(ctx, { kind: 'touch', size: 46 });
  const page = await ctx.newPage();
  await page.goto(FIX, { waitUntil: 'domcontentloaded' });

  // 素材前提：页面得比视口高，不然滚动动作静默无效（踩过）
  const scrollable = await page.evaluate(() =>
    document.documentElement.scrollHeight > document.documentElement.clientHeight + 40);
  scrollable ? ok('fixture 页面高过视口（滚动测得动）') : no('fixture 页面滚不动，测不了滚动');

  // ---------- ① 光标画出来了没 ----------
  const CX = 360, CY = 700, BOX = { x: CX - 45, y: CY - 45, w: 90, h: 90 };
  await page.evaluate((s) => window.__cur.frame(s), { x: CX, y: CY, press: 0, ripple: -1, visible: true });
  const shotOn = await page.screenshot();
  await page.evaluate((s) => window.__cur.frame(s), { x: CX, y: CY, press: 0, ripple: -1, visible: false });
  const shotOff = await page.screenshot();
  const dOn = diff(shotOn, shotOff, BOX);
  dOn > 6 ? ok(`光标在画面上（触点处平均像素差 ${dOn.toFixed(1)}）`)
          : no(`光标没画出来（像素差只有 ${dOn.toFixed(1)}）`);
  const dElse = diff(shotOn, shotOff, { x: 20, y: 20, w: 300, h: 120 });
  dElse < 1.5 ? ok('光标只改触点那一块，没污染别处')
              : no(`光标影响到了无关区域（差 ${dElse.toFixed(1)}）`);

  // ---------- ③ 水波纹按帧推进 ----------
  await page.evaluate((s) => window.__cur.frame(s), { x: CX, y: CY, press: 0, ripple: -1, visible: true });
  const base = await page.screenshot();
  const RB = { x: CX - 80, y: CY - 80, w: 160, h: 160 };
  const seq = [];
  for (const r of [0.1, 0.45, 0.85]) {
    await page.evaluate((s) => window.__cur.frame(s), { x: CX, y: CY, press: 0, ripple: r, visible: true });
    seq.push(diff(await page.screenshot(), base, RB));
  }
  // 同一个 ripple 值必须画出同一帧 —— 有 CSS 动画就会随时间飘
  await page.evaluate((s) => window.__cur.frame(s), { x: CX, y: CY, press: 0, ripple: 0.45, visible: true });
  const again = await page.screenshot();
  await new Promise((r) => setTimeout(r, 700));
  const later = await page.screenshot();
  const drift = diff(again, later, RB);

  seq[0] > 0.5 && seq[1] > 0.5 ? ok(`水波纹画得出来（r=0.1/0.45 差 ${seq[0].toFixed(1)}/${seq[1].toFixed(1)}）`)
                               : no(`水波纹没出现：${seq.map((x) => x.toFixed(1)).join('/')}`);
  seq[2] < seq[1] ? ok('水波纹会衰减（越到后面越淡）') : no('水波纹不衰减');
  drift < 0.4 ? ok('同一个 ripple 值恒定出同一帧（没有按墙上时间跑的动画）')
              : no(`ripple 状态随时间漂了 ${drift.toFixed(2)} —— 有 CSS 动画混进来了`);

  // ---------- ② 动作真作用到页面 ----------
  const acts = [
    { at: 0.1, do: 'tap', to: '#bd' },
    { at: 0.8, do: 'type', text: '1995-08-11 07:30', over: 0.8 },
    { at: 2.0, do: 'tap', to: '#go' },
    { at: 3.0, do: 'wheel', dy: 500, over: 1.0 },
    { at: 4.3, do: 'hide' },
  ];
  const actor = new Actor(page, acts, { fps: FPS, w: W, h: H, log: () => {} });
  let sawRipple = false, focusedAtClick = null;
  for (let i = 0; i < 60; i++) {
    await actor.tick(i);
    if (i === 2) focusedAtClick = null;
    if (actor.rippleFrame >= 0) sawRipple = true;
  }
  const st = await page.evaluate(() => ({
    v: document.getElementById('bd').value,
    out: document.getElementById('out').textContent,
    sy: Math.round(window.scrollY),
  }));

  st.v === '1995-08-11 07:30' ? ok(`type 真打进了输入框（"${st.v}"）`)
                              : no(`输入框里是 "${st.v}"，说明 tap 没点中或没聚焦`);
  st.out.includes('1995-08-11') ? ok('tap 真点到了按钮（页面状态变了）')
                                : no(`按钮没被点到：out="${st.out}"`);
  st.sy > 100 ? ok(`wheel 真滚了页面（scrollY=${st.sy}）`) : no(`页面没滚动（scrollY=${st.sy}）`);
  sawRipple ? ok('点击派生出了水波纹') : no('点击没有水波纹');
  actor.visible === false ? ok('hide 之后光标收起') : no('hide 没生效');

  // tap 的那一下必须落在**移动结束**的位置。曾经先触发动作再走补间，
  // 结果点在上一帧的坐标上 —— 画面里光标明明在按钮上，却点空了。
  const reset = async () => {
    await page.evaluate(() => {
      window.scrollTo(0, 0);               // 上一段把页面滚下去了，先回顶
      const s = document.getElementById('__spacer'); if (s) s.remove();
      document.getElementById('bd').value = '';
      if (document.activeElement) document.activeElement.blur();
    });
    await page.waitForTimeout(400);        // 等滚动惯性停下来，不然测出来是随机的
  };

  await reset();
  const far = new Actor(page, [{ at: 0, do: 'tap', to: '#bd' }], { fps: FPS, w: W, h: H, log: () => {} });
  for (let i = 0; i < 12; i++) await far.tick(i);
  const focused = await page.evaluate(() => (document.activeElement || {}).id);
  focused === 'bd' ? ok('tap 点在移动终点上（不是上一帧的位置）')
                   : no(`tap 点空了，焦点在 "${focused}"`);

  // 移动途中页面挪了位（惯性滚动没停、图片加载完撑高、骨架屏换真内容都会这样）。
  // 落点必须在按下那一刻重新量 —— 用 move 开始时量的旧坐标就会擦边点空，
  // 而画面上光标看着好好地压在按钮上，逐帧看都未必看得出来。
  await reset();
  const shift = new Actor(page, [{ at: 0, do: 'tap', to: '#bd' }], { fps: FPS, w: W, h: H, log: () => {} });
  for (let i = 0; i < 12; i++) {
    await shift.tick(i);
    if (i === 2) await page.evaluate(() => {           // 在目标上方塞 200px，把它挤下去
      const d = document.createElement('div');
      d.id = '__spacer'; d.style.height = '200px';
      document.body.insertBefore(d, document.body.firstChild);
    });
  }
  const f2 = await page.evaluate(() => (document.activeElement || {}).id);
  f2 === 'bd' ? ok('移动途中目标位移了，落点仍然准（按下时重新量过）')
              : no(`目标位移后点空了，焦点在 "${f2}"`);
  await reset();

  // 目标被滚出视口时必须出声，不能画面上光标在点、实际点空
  const warns = [];
  const off = new Actor(page, [], { fps: FPS, w: W, h: H, log: (m) => warns.push(m) });
  await page.evaluate(() => window.scrollTo(0, 400));
  await page.waitForTimeout(200);
  await off._resolve('#bd');
  warns.some((m) => m.includes('视口外')) ? ok('目标滚出视口会警告（点空不再是静默的）')
                                          : no('目标在视口外却没警告');

  await browser.close();
  process.exit(bad ? 1 : 0);
})().catch((e) => { console.log(`  ✗ 崩了: ${e.message}`); process.exit(1); });
