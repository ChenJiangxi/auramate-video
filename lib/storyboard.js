#!/usr/bin/env node
// storyboard.js — 用 storyboard.json 填卡模板 → 渲染成 webm → 直接产出 shots.tsv。
//
// 用法:
//   node lib/storyboard.js --project <dir> [--templates <dir>] [--out html/beats]
//        [--shots shots.tsv] [--gap 0.25] [--no-render] [--w 1080] [--h 1920]
//
// 输入 <project>/storyboard.json:
//   {
//     "accent": "gold",
//     "beats": [
//       {"clip":"c01","template":"hook-slam",
//        "data":{"l1":"AI 算命","l2":"卷成这样了？","sub":"八字 · 合盘","ghost":"?"}},
//       {"clip":"c02","template":"bar-rank","dur":6.5,
//        "data":{"title":"...","rows":[{"rank":1,"name":"X","tag":"Chat","value":40.3,"color":"#7fd0e0"}]}}
//     ]
//   }
//
// 时长来源（优先级）: beat.dur > <project>/audio/<clip>.mp3 时长 + gap > 3.5s 兜底
//   —— 跟 build-vertical.sh 用同一套 audio-driven 规则，两边不会漂。
//
// 产出:
//   <project>/work/cards/<clip>.html   填好的 HTML（可以直接在浏览器里打开调）
//   <project>/html/beats/<clip>.webm   渲染结果
//   <project>/shots.tsv                追加/更新 `clip<TAB>card<TAB><路径><TAB>0`
//
// 模板语法: {{key}} 标量；<!-- repeat:rows --> ... <!-- /repeat --> 数组。
// 故意做得很小 —— 模板要能被人直接读懂和手改，不引第三方模板引擎。

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const argv = process.argv.slice(2);
const arg = (k, d = null) => { const i = argv.indexOf(k); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
const has = (k) => argv.includes(k);

const PROJECT = path.resolve(arg('--project', '.'));
const REPO = path.resolve(__dirname, '..');
const TPL = path.resolve(arg('--templates', path.join(REPO, 'skills/html-motion-cards/templates')));
const OUTDIR = path.resolve(PROJECT, arg('--out', 'html/beats'));
const SHOTS = path.resolve(PROJECT, arg('--shots', 'shots.tsv'));
const GAP = Number(arg('--gap', '0.25'));
const W = Number(arg('--w', '1080'));
const H = Number(arg('--h', '1920'));

const sbPath = path.join(PROJECT, 'storyboard.json');
if (!fs.existsSync(sbPath)) { console.error('找不到', sbPath); process.exit(2); }
const sb = JSON.parse(fs.readFileSync(sbPath, 'utf8'));
if (!Array.isArray(sb.beats) || !sb.beats.length) { console.error('storyboard.json 里没有 beats'); process.exit(2); }

function audioDur(clip) {
  const f = path.join(PROJECT, 'audio', `${clip}.mp3`);
  if (!fs.existsSync(f)) return null;
  try {
    return parseFloat(execFileSync('ffprobe',
      ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', f]).toString().trim());
  } catch { return null; }
}

// ---- 极简模板引擎 ----
function fill(tpl, data) {
  // 先处理数组块，再处理标量，否则块里的 {{key}} 会被外层先吃掉
  let out = tpl.replace(/<!--\s*repeat:(\w+)\s*-->([\s\S]*?)<!--\s*\/repeat\s*-->/g,
    (_, key, body) => {
      const rows = data[key];
      if (!Array.isArray(rows)) return '';
      return rows.map((row, i) => {
        const ctx = { ...row, index: i, delay: (0.15 + i * 0.07).toFixed(2), rkClass: i === 0 ? 'top' : '' };
        return body.replace(/\{\{(\w+)\}\}/g, (m, k) => (ctx[k] !== undefined ? String(ctx[k]) : ''));
      }).join('');
    });
  // 数组自动派生 <name>Count / <name>H（行高 118px），模板里就能把参考线长度跟行数绑起来
  const derived = { ...data };
  for (const [k, v] of Object.entries(data)) {
    if (Array.isArray(v)) { derived[k + 'Count'] = v.length; derived[k + 'H'] = v.length * 118; }
  }
  out = out.replace(/\{\{(\w+)\}\}/g, (m, k) => (derived[k] !== undefined ? String(derived[k]) : ''));
  return out;
}

const workCards = path.join(PROJECT, 'work', 'cards');
fs.mkdirSync(workCards, { recursive: true });
fs.mkdirSync(OUTDIR, { recursive: true });
// _base.css 要跟填好的 HTML 放同一层，相对路径才解析得到
fs.copyFileSync(path.join(TPL, '_base.css'), path.join(workCards, '_base.css'));

const jobs = [];
for (const b of sb.beats) {
  const tplFile = path.join(TPL, `${b.template}.html`);
  if (!fs.existsSync(tplFile)) { console.error(`✗ ${b.clip}: 没有模板 ${b.template}`); process.exit(3); }
  const data = { accent: sb.accent || 'gold', ...(b.data || {}) };
  const html = fill(fs.readFileSync(tplFile, 'utf8'), data);

  let dur = b.dur;
  let src = 'storyboard.json';
  if (dur == null) {
    const ad = audioDur(b.clip);
    if (ad != null) { dur = +(ad + GAP).toFixed(3); src = `audio/${b.clip}.mp3 + gap`; }
    else { dur = 3.5; src = '兜底默认'; }
  }
  const htmlPath = path.join(workCards, `${b.clip}.html`);
  fs.writeFileSync(htmlPath, html);
  jobs.push({ clip: b.clip, template: b.template, htmlPath, dur, src });
  console.log(`  ${b.clip}  ${b.template}  ${dur}s  (${src})`);

  const left = (html.match(/\{\{(\w+)\}\}/g) || []);
  if (left.length) console.warn(`    ! ${b.clip} 还有没填的占位符: ${[...new Set(left)].join(' ')}`);
}

// ---- shots.tsv：合并写，保留别的行 ----
function writeShots() {
  const lines = new Map();
  if (fs.existsSync(SHOTS)) {
    for (const l of fs.readFileSync(SHOTS, 'utf8').split('\n')) {
      const c = l.split('\t')[0];
      if (c) lines.set(c, l);
    }
  }
  for (const j of jobs) {
    const rel = path.relative(PROJECT, path.join(OUTDIR, `${j.clip}.webm`));
    lines.set(j.clip, `${j.clip}\tcard\t${rel}\t0`);
  }
  const order = sb.beats.map(b => b.clip);
  const rest = [...lines.keys()].filter(c => !order.includes(c));
  fs.writeFileSync(SHOTS, [...order, ...rest].map(c => lines.get(c)).filter(Boolean).join('\n') + '\n');
  console.log(`shots.tsv → ${SHOTS}  (${lines.size} 行)`);
}

if (has('--no-render')) {
  writeShots();
  console.log('--no-render：只填了模板、写了 shots.tsv，没渲染。');
  console.log(`填好的 HTML 在 ${workCards}，可以直接用浏览器打开调样式。`);
  process.exit(0);
}

let chromium;
try { ({ chromium } = require('playwright')); }
catch {
  console.error('缺 playwright（npm i playwright && npx playwright install chromium）');
  console.error('只想产出 HTML + shots.tsv 的话加 --no-render');
  process.exit(4);
}

(async () => {
  const browser = await chromium.launch({ headless: true,
    args: ['--autoplay-policy=no-user-gesture-required'] });
  let okN = 0;
  for (const j of jobs) {
    const tmp = path.join(OUTDIR, `.${j.clip}`);
    fs.mkdirSync(tmp, { recursive: true });
    // recordVideo.size 必须 === viewport，不然内容只填左上角
    const ctx = await browser.newContext({
      viewport: { width: W, height: H }, deviceScaleFactor: 1, locale: 'zh-CN',
      recordVideo: { dir: tmp, size: { width: W, height: H } },
    });
    const page = await ctx.newPage();
    await page.goto('file://' + j.htmlPath, { waitUntil: 'load', timeout: 30000 });
    await page.waitForTimeout(Math.round(j.dur * 1000));
    await page.close();
    await ctx.close();                       // 必须 close context 才 flush 出 webm
    const f = fs.readdirSync(tmp).find(n => n.endsWith('.webm'));
    const dst = path.join(OUTDIR, `${j.clip}.webm`);
    if (f) { fs.renameSync(path.join(tmp, f), dst); okN++; console.log(`  ✓ ${j.clip} → ${dst}`); }
    else console.error(`  ✗ ${j.clip} 没生成视频`);
    fs.rmSync(tmp, { recursive: true, force: true });
  }
  await browser.close();
  writeShots();
  console.log(`\n渲染完成 ${okN}/${jobs.length}`);
  console.log('下一步: lib/build-vertical.sh --project ' + PROJECT + ' --shots ' + SHOTS);
  process.exit(okN === jobs.length ? 0 : 1);
})().catch(e => { console.error('FATAL', e.message); process.exit(1); });
