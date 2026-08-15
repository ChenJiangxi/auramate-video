// _pngdiff.js — 只解自家 Chromium 截出来的 8bit PNG，算两张图在某块矩形里的平均像素差。
// cursor-test.js / highlight-test.js 共用。不引第三方库：validate.sh 要能在干净机器上跑。
'use strict';
const zlib = require('zlib');

function decode(buf) {
  let p = 8, w = 0, h = 0, bd = 0, ct = 0, idat = [];
  while (p < buf.length) {
    const len = buf.readUInt32BE(p), type = buf.toString('ascii', p + 4, p + 8);
    const data = buf.slice(p + 8, p + 8 + len);
    if (type === 'IHDR') { w = data.readUInt32BE(0); h = data.readUInt32BE(4); bd = data[8]; ct = data[9]; }
    else if (type === 'IDAT') idat.push(data);
    else if (type === 'IEND') break;
    p += 12 + len;
  }
  if (bd !== 8 || (ct !== 6 && ct !== 2)) throw new Error(`不支持的 PNG bd=${bd} ct=${ct}`);
  const ch = ct === 6 ? 4 : 3;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * ch, out = Buffer.alloc(h * stride);
  let q = 0;
  for (let y = 0; y < h; y++) {
    const f = raw[q++];
    for (let x = 0; x < stride; x++) {
      const v = raw[q + x];
      const A = x >= ch ? out[y * stride + x - ch] : 0;
      const B = y > 0 ? out[(y - 1) * stride + x] : 0;
      const C = x >= ch && y > 0 ? out[(y - 1) * stride + x - ch] : 0;
      let r;
      if (f === 0) r = v; else if (f === 1) r = v + A; else if (f === 2) r = v + B;
      else if (f === 3) r = v + ((A + B) >> 1);
      else { const pp = A + B - C, pa = Math.abs(pp - A), pb = Math.abs(pp - B), pc = Math.abs(pp - C);
             r = v + (pa <= pb && pa <= pc ? A : pb <= pc ? B : C); }
      out[y * stride + x] = r & 255;
    }
    q += stride;
  }
  return { w, h, ch, out };
}

// 平均通道差（0–255）。box 超出画面会自动夹住。
function diff(a, b, box) {
  const A = decode(a), B = decode(b);
  const x0 = Math.max(0, Math.round(box.x)), y0 = Math.max(0, Math.round(box.y));
  const x1 = Math.min(A.w, Math.round(box.x + box.w)), y1 = Math.min(A.h, Math.round(box.y + box.h));
  let s = 0, n = 0;
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
    for (let c = 0; c < 3; c++) {
      s += Math.abs(A.out[y * A.w * A.ch + x * A.ch + c] - B.out[y * B.w * B.ch + x * B.ch + c]); n++;
    }
  }
  return n ? s / n : 0;
}

// 平均亮度（0–255）。暗场测的是「周围变暗了」，看差值不够 —— 得看往哪个方向变。
function luma(a, box) {
  const A = decode(a);
  const x0 = Math.max(0, Math.round(box.x)), y0 = Math.max(0, Math.round(box.y));
  const x1 = Math.min(A.w, Math.round(box.x + box.w)), y1 = Math.min(A.h, Math.round(box.y + box.h));
  let s = 0, n = 0;
  for (let y = y0; y < y1; y++) for (let x = x0; x < x1; x++) {
    const i = y * A.w * A.ch + x * A.ch;
    s += 0.299 * A.out[i] + 0.587 * A.out[i + 1] + 0.114 * A.out[i + 2]; n++;
  }
  return n ? s / n : 0;
}

module.exports = { decode, diff, luma };
