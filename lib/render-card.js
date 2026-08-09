#!/usr/bin/env node
// render-card.js — 把一个 HTML 卡渲成视频或静图。
//
// 用法:
//   node lib/render-card.js --html html/cards/hook.html --out html/beats/hook.webm \
//        [--w 1080] [--h 1920] [--duration 4] [--png]
//
// 约束和录网页一样: recordVideo.size 必须 === viewport。
// 动画建议 3–5s 内跑完，多余时长后期 trim 不影响观感。
const path = require('path');
const fs = require('fs');

let chromium;
try { ({ chromium } = require('playwright')); }
catch { console.error('缺 playwright: npm i playwright && npx playwright install chromium'); process.exit(2); }

const argv = process.argv.slice(2);
const arg = (k, d = null) => { const i = argv.indexOf(k); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
const has = (k) => argv.includes(k);

const HTML = arg('--html');
const OUT = arg('--out');
if (!HTML || !OUT) { console.error('需要 --html <file> --out <file>'); process.exit(2); }
if (!fs.existsSync(HTML)) { console.error('HTML 不存在:', HTML); process.exit(2); }

const VP = { width: Number(arg('--w', 1080)), height: Number(arg('--h', 1920)) };
const DUR = Number(arg('--duration', 4)) * 1000;
const fileUrl = 'file://' + path.resolve(HTML);
fs.mkdirSync(path.dirname(OUT), { recursive: true });

(async () => {
  const browser = await chromium.launch({ headless: true });

  if (has('--png')) {
    const ctx = await browser.newContext({ viewport: VP, deviceScaleFactor: 2 });
    const page = await ctx.newPage();
    await page.goto(fileUrl, { waitUntil: 'networkidle', timeout: 30000 });
    await page.waitForTimeout(Math.min(DUR, 6000));   // 等动画走完再截
    await page.screenshot({ path: OUT });
    await ctx.close(); await browser.close();
    console.log('PNG', OUT);
    console.log('提醒: -loop 1 读这张图时必须配 -t <时长>，否则 ffmpeg 永不结束');
    return;
  }

  const TMP = path.join(path.dirname(OUT), '.cardwork');
  fs.mkdirSync(TMP, { recursive: true });
  const ctx = await browser.newContext({
    viewport: VP, deviceScaleFactor: 2,
    recordVideo: { dir: TMP, size: VP },              // ← 必须等于 viewport
  });
  const page = await ctx.newPage();
  await page.goto(fileUrl, { waitUntil: 'networkidle', timeout: 30000 });
  await page.waitForTimeout(DUR);
  await page.close(); await ctx.close();              // close 才 flush

  const f = fs.readdirSync(TMP).find(n => n.endsWith('.webm'));
  if (f) { fs.renameSync(path.join(TMP, f), OUT); console.log('VIDEO', OUT); }
  else console.error('NO VIDEO');
  fs.rmSync(TMP, { recursive: true, force: true });
  await browser.close();
  process.exit(f ? 0 : 1);
})().catch(e => { console.error('FATAL', e.message); process.exit(1); });
