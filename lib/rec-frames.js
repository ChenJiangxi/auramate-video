#!/usr/bin/env node
// rec-frames.js — 高分辨率录网页：**保持移动端布局**，同时拿到 2–3 倍像素。
//
// 为什么不用 recordVideo：
//   recordVideo 的画面尺寸 = viewport 的 CSS 尺寸，deviceScaleFactor 不起作用。
//   想要更多像素只能把 viewport 调宽 —— 但一调宽，网站的响应式断点就切到桌面布局：
//   主视觉缩到角落、文字挤成一条、大片留白，作为竖版素材直接报废（真踩过）。
//
//   正确做法是**布局用窄 viewport，像素用 deviceScaleFactor**，
//   然后逐帧截图（screenshot 是认 dsf 的），最后拼成视频。
//   viewport 720×1280 + dsf 3 → 每帧 2160×3840，输出 1080 时还有 2× 余量可以推镜。
//
// 用法:
//   node lib/rec-frames.js --url <URL> --out footage/rec/x.mp4
//        [--w 720] [--h 1280] [--dsf 3] [--fps 12] [--secs 12]
//        [--scroll 340] [--scroll-every 3]      # 每隔几帧滚一次、滚多少
//        [--cursor touch|arrow] [--cursor-size 46]   # 画一个看得见的手指/箭头
//        [--act actions.json]                   # 动作表：移动/点/打字/滚（见 lib/actor.js）
//        [--login-url ... --email ... --pw-env MY_PW]
//        [--click-start]                        # 先点「开始/生成」再等结果
//        [--keep-frames]                        # 保留 PNG 序列
//
// 关于光标：截图里**没有系统光标**。不画的话页面像自己在动、输入框像自己在填字，
// 观众看不出有人在操作。--cursor 注入一个自绘光标，--act 让它真的去点。
// 两者都按帧推进（截一帧的墙上时间不均匀，按时间跑的动画在成片里会忽快忽慢）。
//
// 代价：比 recordVideo 慢（每帧一次截图）。12fps × 12s = 144 帧，约 1–2 分钟。
// 换来的是真实分辨率 —— 推镜的前提。
const { execFileSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const { installCursor, installCursorNow } = require('./cursor-overlay');
const { Actor } = require('./actor');

let chromium;
try { ({ chromium } = require('playwright')); }
catch { console.error('缺 playwright: npm i playwright && npx playwright install chromium'); process.exit(2); }

const argv = process.argv.slice(2);
const arg = (k, d = null) => { const i = argv.indexOf(k); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
const has = (k) => argv.includes(k);

const URL = arg('--url');
const OUT = arg('--out');
if (!URL || !OUT) { console.error('需要 --url 和 --out'); process.exit(2); }

const W = Number(arg('--w', 720));       // CSS 宽度：决定布局，别乱调大
const H = Number(arg('--h', 1280));
const DSF = Number(arg('--dsf', 3));     // 像素倍数：决定清晰度，推镜靠它
const FPS = Number(arg('--fps', 12));
const SECS = Number(arg('--secs', 12));
const SCROLL = Number(arg('--scroll', 340));
const EVERY = Number(arg('--scroll-every', 3));
// --cursor 后面可以不跟值（默认 touch）；跟的要是下一个开关就当没写
let CURSOR = null;
if (has('--cursor')) {
  const v = arg('--cursor', 'touch');
  CURSOR = (!v || v.startsWith('--')) ? 'touch' : v;
}
const CURSIZE = Number(arg('--cursor-size', 46));
const ACTFILE = arg('--act');
// 有动作表却看不见光标 = 页面在自己动，等于白做。除非明确 --no-cursor
if (ACTFILE && !CURSOR && !has('--no-cursor')) CURSOR = 'touch';
let ACTIONS = null;
if (ACTFILE) {
  if (!fs.existsSync(ACTFILE)) { console.error(`找不到动作表 ${ACTFILE}`); process.exit(2); }
  try { ACTIONS = JSON.parse(fs.readFileSync(ACTFILE, 'utf8')); }
  catch (e) { console.error(`动作表不是合法 JSON: ${e.message}`); process.exit(2); }
  if (!Array.isArray(ACTIONS)) { console.error('动作表要是一个数组'); process.exit(2); }
}
const MOBILE_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Mobile/15E148 Safari/604.1';

const TMP = path.join(path.dirname(OUT), '.frames');
fs.rmSync(TMP, { recursive: true, force: true });
fs.mkdirSync(TMP, { recursive: true });
fs.mkdirSync(path.dirname(OUT), { recursive: true });

async function login(page) {
  const loginUrl = arg('--login-url'), email = arg('--email'), pwEnv = arg('--pw-env');
  if (!loginUrl) return null;
  const pw = pwEnv ? process.env[pwEnv] : null;
  if (!pw) { console.error(`需要环境变量 ${pwEnv} 提供密码（别写进命令行）`); process.exit(2); }
  await page.goto(loginUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(1500);
  const tab = page.getByRole('button', { name: /密码登录|Password/ }).first();
  if (await tab.count().catch(() => 0)) { try { await tab.click({ timeout: 1500 }); } catch {} }
  await page.waitForTimeout(500);
  const em = page.locator('input[type="email"],input[placeholder*="邮箱"],input[placeholder*="账号"]').first();
  if (await em.count()) await em.fill(email);
  else await page.locator('input:not([type="password"])').first().fill(email);
  await page.locator('input[type="password"]').first().fill(pw);
  try { await page.locator('button[type="submit"]').first().click({ timeout: 2500 }); } catch {}
  await page.waitForTimeout(6000);
  console.log('login done ->', page.url());
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  const ctxOpts = {
    viewport: { width: W, height: H },     // 窄 → 保住移动端布局
    deviceScaleFactor: DSF,                // 高 → 真实像素，screenshot 认这个
    isMobile: true, hasTouch: true, userAgent: MOBILE_UA, locale: 'zh-CN',
  };

  let state;
  if (arg('--login-url')) {
    const c1 = await browser.newContext(ctxOpts);
    await login(await c1.newPage());
    state = await c1.storageState();
    await c1.close();
  }
  const ctx = await browser.newContext({ ...ctxOpts, ...(state ? { storageState: state } : {}) });
  if (CURSOR) await installCursor(ctx, { kind: CURSOR, size: CURSIZE });
  const page = await ctx.newPage();

  try { await page.goto(URL, { waitUntil: 'commit', timeout: 60000 }); }
  catch { console.log('goto slow, continuing'); }
  await page.waitForTimeout(5000);
  // addInitScript 只对之后的导航生效；页面已经在了就再补一次，两条路都保住
  if (CURSOR) await installCursorNow(page, { kind: CURSOR, size: CURSIZE }).catch(() => {});

  if (has('--click-start')) {
    const btn = page.locator('button:has-text("开始"), button:has-text("生成")').first();
    if (await btn.count().catch(() => 0)) {
      await btn.click({ timeout: 3000 }).catch(() => {});
      for (let k = 0; k < 30; k++) {
        await page.waitForTimeout(2000);
        const still = await page.locator('button:has-text("开始"), button:has-text("生成")').count().catch(() => 0);
        const len = await page.evaluate(() => document.body.innerText.length).catch(() => 0);
        if (!still && len > 900) { console.log('ready @', k * 2 + 's'); break; }
      }
      await page.waitForTimeout(2500);
    }
  }

  await page.mouse.move(W / 2, H / 2);
  const total = Math.round(FPS * SECS);
  const interval = 1000 / FPS;
  const actor = ACTIONS
    ? new Actor(page, ACTIONS, { fps: FPS, w: W, h: H, log: (m) => console.log(m) })
    : null;
  console.log(`逐帧截图 ${total} 帧 @ ${W * DSF}×${H * DSF}（布局 ${W}×${H}，dsf ${DSF}）`
    + (CURSOR ? ` · 光标 ${CURSOR}` : '') + (actor ? ` · 动作 ${ACTIONS.length} 条` : ''));
  for (let i = 0; i < total; i++) {
    // 先把这一帧该有的状态摆好，再截。顺序反了就永远慢一帧。
    if (actor) await actor.tick(i);
    else if (CURSOR) await page.evaluate(() => window.__cur && window.__cur.ensure()).catch(() => {});
    await page.screenshot({ path: path.join(TMP, `f${String(i).padStart(5, '0')}.png`) });
    // 老的定时滚动：只在没给动作表时还管用（给了就由动作表说了算）
    if (!actor && EVERY > 0 && SCROLL !== 0 && i > 0 && i % EVERY === 0) {
      await page.mouse.wheel(0, SCROLL);       // SPA 多是内层容器滚动，wheel 才有效
    }
    await page.waitForTimeout(interval);
    if ((i + 1) % 24 === 0) process.stdout.write(`  ${i + 1}/${total}\r`);
  }
  console.log(`\n截图完成`);
  await page.close(); await ctx.close(); await browser.close();

  execFileSync('ffmpeg', ['-nostdin', '-y', '-v', 'error', '-framerate', String(FPS),
    '-i', path.join(TMP, 'f%05d.png'),
    '-vf', `fps=30,format=yuv420p`, '-c:v', 'libx264', '-crf', '18', OUT], { stdio: 'inherit' });

  const probe = execFileSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0',
    '-show_entries', 'stream=width,height', '-show_entries', 'format=duration',
    '-of', 'csv=p=0', OUT]).toString().trim().split('\n');
  console.log(`VIDEO ${OUT}  ${probe[0]}  ${probe[1]}s`);
  if (!has('--keep-frames')) fs.rmSync(TMP, { recursive: true, force: true });
  process.exit(0);
})().catch(e => { console.error('FATAL', e.message); process.exit(1); });
