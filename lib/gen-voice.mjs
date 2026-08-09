#!/usr/bin/env node
// gen-voice.mjs — MiniMax T2A v2 批量生成口播配音。
//
// 用法:
//   MINIMAX_API_KEY=... node lib/gen-voice.mjs --clips clips.json --out audio/ \
//        [--voice presenter_male] [--speed 1.28] [--model speech-2.5-hd-preview] [--force]
//
//   # 音色候选采样（同一句话跑多个音色，打包给人类挑）
//   MINIMAX_API_KEY=... node lib/gen-voice.mjs --sample --text "他三天没回。" --out audio/samples/
//
// 环境变量:
//   MINIMAX_API_KEY   必须。绝不写进代码、日志、commit。
//   MINIMAX_API_BASE  可选，默认 https://api.minimax.io/v1（国际区）。
//                     国内区账号要设成 https://api.minimaxi.com/v1，否则报 2049。
//
// 注意: 返回的 data.audio 是 hex 字符串，不是 base64。

import { writeFileSync, mkdirSync, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';

const argv = process.argv.slice(2);
const arg = (k, d = null) => { const i = argv.indexOf(k); return i >= 0 && argv[i + 1] ? argv[i + 1] : d; };
const has = (k) => argv.includes(k);

const KEY = process.env.MINIMAX_API_KEY;
if (!KEY) { console.error('缺 MINIMAX_API_KEY（见 SECRETS-CHECKLIST.md）'); process.exit(2); }
const API = (process.env.MINIMAX_API_BASE || 'https://api.minimax.io/v1') + '/t2a_v2';
const MODEL = arg('--model', 'speech-2.5-hd-preview');
const OUT = arg('--out', 'audio');
mkdirSync(OUT, { recursive: true });

// 采样用的候选音色 —— 题材对应见 skills/tts-voiceover/SKILL.md
const SAMPLE_VOICES = ['presenter_male', 'female-tianmei', 'female-shaonv'];

async function tts(text, voice_id, speed) {
  const r = await fetch(API, {
    method: 'POST',
    headers: { Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: MODEL,
      text,
      voice_setting: { voice_id, speed: Number(speed), vol: 1.0, pitch: 0 },
      audio_setting: { sample_rate: 32000, bitrate: 128000, format: 'mp3', channel: 1 },
      language_boost: 'Chinese',
      subtitle_enable: false,
    }),
  });
  const j = await r.json().catch(() => ({}));
  // 一定要看 base_resp.status_code，HTTP 200 不代表成功
  if (j?.base_resp?.status_code !== 0) {
    const br = j?.base_resp || j;
    console.error('  ERR', JSON.stringify(br).slice(0, 200));
    if (br?.status_code === 1008) console.error('  → 1008: 充 pay-as-you-go 余额（credits 池不给 TTS 用）');
    if (br?.status_code === 2042) console.error('  → 2042: 这个 key 没有该 voice_id 权限');
    if (br?.status_code === 2049) console.error('  → 2049: key 和区域对不上，检查 MINIMAX_API_BASE');
    return null;
  }
  return j?.data?.audio || null;
}

function warnText(t, name) {
  if (/(^|[^A-Za-z])ta([^A-Za-z]|$)/i.test(t)) console.warn(`  ⚠ ${name}: 文本里有 "ta"，TTS 会念成 T-A —— 改成 他/她`);
  if (t.length > 30) console.warn(`  ⚠ ${name}: ${t.length} 字，单句偏长，建议 ≤30 字`);
  if (/<#[\d.]+#>/.test(t)) console.warn(`  ⚠ ${name}: 带显式停顿标记，建议改用自然标点`);
}

if (has('--sample')) {
  const text = arg('--text');
  if (!text) { console.error('--sample 需要 --text "一句话"'); process.exit(2); }
  const speed = arg('--speed', '1.28');
  warnText(text, 'sample');
  for (const v of SAMPLE_VOICES) {
    process.stdout.write(`[sample] ${v} @${speed} ... `);
    const hex = await tts(text, v, speed);
    if (!hex) { console.log('FAIL'); continue; }
    const o = join(OUT, `sample-${v}-${speed}.mp3`);
    writeFileSync(o, Buffer.from(hex, 'hex'));
    console.log('ok ->', o);
  }
  console.log('\n把这几个采样发给人类挑一个，别自己拍板。');
  process.exit(0);
}

const clipsPath = arg('--clips', 'clips.json');
if (!existsSync(clipsPath)) { console.error('找不到', clipsPath); process.exit(2); }
const clips = JSON.parse(readFileSync(clipsPath, 'utf8'));
const VOICE = arg('--voice');
if (!VOICE) { console.error('需要 --voice <voice_id>（先用 --sample 让人类挑）'); process.exit(2); }
const SPEED = arg('--speed', '1.28');

let okN = 0, failN = 0;
for (const c of clips) {
  const o = join(OUT, `${c.name}.mp3`);
  if (existsSync(o) && !has('--force')) { console.log('[skip]', c.name); okN++; continue; }
  warnText(c.text, c.name);
  process.stdout.write(`[gen] ${c.name} (${c.text.length}字) ... `);
  const hex = await tts(c.text, VOICE, SPEED);
  if (!hex) { console.log('FAIL'); failN++; continue; }
  writeFileSync(o, Buffer.from(hex, 'hex'));
  console.log('ok');
  okN++;
}
console.log(`\n[done] ${okN} ok / ${failN} fail`);
console.log('下一步必须跑: lib/verify-audio.sh ' + OUT + ' ' + clipsPath);
process.exit(failN ? 1 : 0);
