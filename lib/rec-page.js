#!/usr/bin/env node
// rec-page.js — Playwright 录网页做产品演示段（recordVideo 路线，快但只有 CSS 分辨率）。
//
// ⚠ 要推镜的素材别用这个：recordVideo 的尺寸 = viewport 的 CSS 尺寸，
//   deviceScaleFactor 不起作用；把 viewport 调宽换像素会触发网站的桌面断点，
//   布局直接废掉。高分辨率用 lib/rec-frames.js（窄布局 + dsf 逐帧截图）。
//
// 用法:
//   node lib/rec-page.js --url https://example.com/app --out footage/rec/demo.webm
//        [--w 720] [--h 1280] [--scroll 16] [--wait 5000] [--mobile]
//        [--cursor touch|arrow]  # 画一个看得见的手指（截图/录屏都不含系统光标）
//        [--login-url ... --email ... --pw-env MY_PW_ENV]
//        [--click-start]        # 页面需要先点"开始/生成"再等报告出来
//
// ⚠ 这里的光标只是「跟着真实鼠标事件走」，做不了按帧编排的点按演示 ——
//   recordVideo 是浏览器自己按墙上时间录的，脚本插不进「每帧摆一次状态」。
//   要动作表（--act：移动/点/打字/滚，还有水波纹）就用 lib/rec-frames.js。
//
// 三条硬约束（踩过的坑，别改）:
//   1. recordVideo.size 必须 === viewport，不然内容只填左上角
//   2. SPA 冷加载用 waitUntil:'commit' + timeout 60s + try/catch，别用 domcontentloaded
//   3. 很多 SPA 是内层容器滚动，window.scrollTo 无效 → mouse.move + mouse.wheel
//
// 密码只从环境变量读，绝不写进代码/命令行/日志。
const path = require('path');
const fs = require('fs');
const { installCursor, installCursorNow } = require('./cursor-overlay');

let chromium;
try { ({ chromium } = require('playwright')); }
catch { console.error('缺 playwright: npm i playwright && npx playwright install chromium'); process.exit(2); }

const argv = process.argv.slice(2);
const arg = (k, d = null) => { const i = argv.indexOf(k); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
const has = (k) => argv.includes(k);

const URL = arg('--url');
const OUT = arg('--out', 'footage/rec/page.webm');
if (!URL) { console.error('需要 --url'); process.exit(2); }

const VP = { width: Number(arg('--w', 720)), height: Number(arg('--h', 1280)) };
const SCROLLS = Number(arg('--scroll', 16));
const WAIT = Number(arg('--wait', 5000));
let CURSOR = null;
if (has('--cursor')) {
  const v = arg('--cursor', 'touch');
  CURSOR = (!v || v.startsWith('--')) ? 'touch' : v;
}
const MOBILE_UA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Mobile/15E148 Safari/604.1';

const CTX = {
  viewport: VP,
  deviceScaleFactor: 2,          // 2× 像素，后期升采样才有料
  locale: 'zh-CN',
  ...(has('--mobile') ? { isMobile: true, hasTouch: true, userAgent: MOBILE_UA } : {}),
};

const TMP = path.join(path.dirname(OUT), '.recwork');
fs.mkdirSync(TMP, { recursive: true });
fs.mkdirSync(path.dirname(OUT), { recursive: true });

async function login(page) {
  const loginUrl = arg('--login-url'), email = arg('--email'), pwEnv = arg('--pw-env');
  if (!loginUrl) return null;
  const pw = pwEnv ? process.env[pwEnv] : null;
  if (!pw) { console.error(`需要环境变量 ${pwEnv} 提供密码（不要写在命令行里）`); process.exit(2); }
  await page.goto(loginUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await page.waitForTimeout(1500);
  // 有些站默认是验证码登录，要先切到"密码登录" tab
  const tab = page.getByRole('button', { name: /密码登录|Password/ }).first();
  if (await tab.count().catch(() => 0)) { try { await tab.click({ timeout: 1500 }); } catch {} }
  await page.waitForTimeout(500);
  const emailInput = page.locator('input[type="email"],input[placeholder*="邮箱"],input[placeholder*="账号"]').first();
  if (await emailInput.count()) await emailInput.fill(email);
  else await page.locator('input:not([type="password"])').first().fill(email);
  await page.locator('input[type="password"]').first().fill(pw);
  try { await page.locator('button[type="submit"]').first().click({ timeout: 2500 }); } catch {}
  await page.waitForTimeout(6000);
  console.log('login done ->', page.url());
}

(async () => {
  const browser = await chromium.launch({ headless: true });
  let storageState;

  if (arg('--login-url')) {
    const c1 = await browser.newContext(CTX);
    await login(await c1.newPage());
    storageState = await c1.storageState();     // 登录一次，录制 context 复用登录态
    await c1.close();
  }

  const ctx = await browser.newContext({
    ...CTX,
    ...(storageState ? { storageState } : {}),
    recordVideo: { dir: TMP, size: VP },        // ← 必须等于 viewport
  });
  if (CURSOR) await installCursor(ctx, { kind: CURSOR });
  const page = await ctx.newPage();

  // SPA 冷加载会把 goto 拖超时 —— commit + 长 timeout + try/catch
  try { await page.goto(URL, { waitUntil: 'commit', timeout: 60000 }); }
  catch { console.log('goto slow, continuing'); }
  await page.waitForTimeout(WAIT);
  if (CURSOR) await installCursorNow(page, { kind: CURSOR }).catch(() => {});

  if (has('--click-start')) {
    const btn = page.locator('button:has-text("开始"), button:has-text("生成")').first();
    if (await btn.count().catch(() => 0)) {
      console.log('clicking start, polling for result...');
      await btn.click({ timeout: 3000 }).catch(() => {});
      for (let k = 0; k < 30; k++) {                       // 最多等 60s
        await page.waitForTimeout(2000);
        const stillEntry = await page.locator('button:has-text("开始"), button:has-text("生成")').count().catch(() => 0);
        const len = await page.evaluate(() => document.body.innerText.length).catch(() => 0);
        if (!stillEntry && len > 900) { console.log('ready @', k * 2 + 's'); break; }
      }
      await page.waitForTimeout(3000);
    }
  }

  // 内层容器滚动：window.scrollTo 对很多 SPA 无效
  await page.mouse.move(VP.width / 2, VP.height / 2);
  for (let i = 0; i < SCROLLS; i++) {
    await page.mouse.wheel(0, 340);
    await page.waitForTimeout(820);              // 慢滚才好看，也给懒加载时间
  }
  await page.waitForTimeout(1200);

  await page.close();
  await ctx.close();                             // 必须 close context，视频才 flush 出来

  const f = fs.readdirSync(TMP).find(n => n.endsWith('.webm'));
  if (f) { fs.renameSync(path.join(TMP, f), OUT); console.log('VIDEO', OUT); }
  else console.error('NO VIDEO —— 检查 context 是否正常关闭');
  fs.rmSync(TMP, { recursive: true, force: true });
  await browser.close();
  process.exit(f ? 0 : 1);
})().catch(e => { console.error('FATAL', e.message); process.exit(1); });
