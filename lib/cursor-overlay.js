// cursor-overlay.js — 给录屏画一个看得见的手指/光标，以及点按的水波纹。
//
// 为什么要自己画：Playwright 截图和 recordVideo 都**不含系统光标**。不画的话，
// 页面会自己动、输入框会自己填字，观众看不到是谁在操作 —— 像 bug 不像演示。
//
// ⚠ 一条硬规矩：光标的动画不许用 CSS animation / transition。
//   截图是逐帧同步取的，每帧的墙上时间间隔并不均匀（一帧要 100–300ms，还会抖），
//   而 CSS 动画按墙上时间跑。两者一混，输出视频里的水波纹就会忽快忽慢。
//   正确做法和音频驱动时间轴同理：**帧序号就是时钟**，每帧显式把状态摆好再截图。
//   所以这里只暴露 `__cur.frame({x,y,press,ripple})`，一切进度由外部按帧算。
//
// 两种形态:
//   touch  半透明圆点 + 按下水波纹  ← 默认。录的是移动端布局，观众预期是手指
//   arrow  桌面箭头
//
// 用法（rec-frames.js / rec-page.js 已接好，一般不用直接调）:
//   const { installCursor } = require('./cursor-overlay');
//   await installCursor(context, { kind: 'touch', size: 46 });
//   await page.evaluate(s => window.__cur.frame(s), { x: 360, y: 800, press: 0, ripple: -1 });

'use strict';

// 这个函数会被序列化后注入页面，**不能引用外部作用域的任何东西**。
function OVERLAY(opts) {
  if (window.__cur) { window.__cur.ensure(); return; }
  const KIND = opts.kind || 'touch';
  const SIZE = opts.size || 46;
  const NS = 'http://www.w3.org/2000/svg';

  const ARROW = 'M3,2 L3,25 L9,19.5 L13,28 L17.5,26 L13.5,17.8 L21,17.5 Z';
  let root = null, dot = null, ring = null;
  let st = { x: -999, y: -999, press: 0, ripple: -1, visible: true };

  function build() {
    root = document.createElement('div');
    root.id = '__cursor_overlay';
    root.setAttribute('data-cursor-overlay', '1');
    root.style.cssText =
      'position:fixed;left:0;top:0;width:0;height:0;margin:0;padding:0;border:0;' +
      'z-index:2147483647;pointer-events:none;';

    // 水波纹：点按时从触点扩出去。半径/透明度全由外部按帧给，这里不做动画。
    ring = document.createElement('div');
    ring.style.cssText =
      'position:fixed;border-radius:50%;pointer-events:none;opacity:0;' +
      'border:3px solid rgba(255,255,255,.95);' +
      'box-shadow:0 0 0 2px rgba(0,0,0,.22),0 0 22px rgba(255,255,255,.5);' +
      'transform:translate(-50%,-50%);will-change:width,height,opacity;';
    root.appendChild(ring);

    if (KIND === 'arrow') {
      const svg = document.createElementNS(NS, 'svg');
      svg.setAttribute('viewBox', '0 0 30 30');
      svg.setAttribute('width', String(SIZE));
      svg.setAttribute('height', String(SIZE));
      svg.style.cssText = 'position:fixed;pointer-events:none;overflow:visible;' +
        'filter:drop-shadow(0 2px 5px rgba(0,0,0,.45));will-change:transform;';
      const p = document.createElementNS(NS, 'path');
      p.setAttribute('d', ARROW);
      p.setAttribute('fill', '#fff');
      p.setAttribute('stroke', 'rgba(20,20,24,.85)');
      p.setAttribute('stroke-width', '1.6');
      p.setAttribute('stroke-linejoin', 'round');
      svg.appendChild(p);
      dot = svg;
      dot.__anchor = 'tip';          // 箭头以左上尖端为锚点
    } else {
      dot = document.createElement('div');
      dot.style.cssText =
        'position:fixed;width:' + SIZE + 'px;height:' + SIZE + 'px;border-radius:50%;' +
        'pointer-events:none;transform:translate(-50%,-50%);' +
        // 亮底暗底都要看得见：淡白芯 + 深描边 + 外发光。
        // 芯不能太实 —— 观众看产品片是来读界面的，手指盖住按钮上的字就白录了。
        // 靠描边和投影撑存在感，芯留透。
        'background:radial-gradient(circle at 38% 34%, rgba(255,255,255,.55) 0%,' +
        ' rgba(255,255,255,.34) 52%, rgba(255,255,255,.16) 100%);' +
        'border:2px solid rgba(24,24,28,.62);' +
        'box-shadow:0 2px 10px rgba(0,0,0,.40), 0 0 0 1.5px rgba(255,255,255,.55) inset;' +
        'will-change:transform;';
      dot.__anchor = 'center';
    }
    root.appendChild(dot);
  }

  // SPA 重绘可能把 body 整个换掉，光标就没了。每帧调一次，掉了就重新挂。
  function ensure() {
    if (!root) build();
    const host = document.body || document.documentElement;
    if (!host) return false;
    if (root.parentNode !== host) host.appendChild(root);
    return true;
  }

  function paint() {
    if (!ensure()) return;
    const vis = st.visible && st.x > -900;
    dot.style.display = vis ? 'block' : 'none';
    if (vis) {
      const s = 1 - 0.18 * Math.max(0, Math.min(1, st.press));
      if (dot.__anchor === 'tip') {
        dot.style.left = st.x + 'px';
        dot.style.top = st.y + 'px';
        dot.style.transform = 'scale(' + s + ')';
        dot.style.transformOrigin = '0 0';
      } else {
        dot.style.left = st.x + 'px';
        dot.style.top = st.y + 'px';
        dot.style.transform = 'translate(-50%,-50%) scale(' + s + ')';
      }
    }
    // ripple ∈ [0,1)：0 刚按下，1 消失。半径线性张开，透明度按 1.4 次幂衰减 ——
    // 平方衰得太快，一半寿命就已经看不见了，成片里只剩「闪一下」。
    const r = st.ripple;
    if (r >= 0 && r < 1 && vis) {
      const d = SIZE * (0.6 + 2.3 * r);
      ring.style.display = 'block';
      ring.style.left = st.x + 'px';
      ring.style.top = st.y + 'px';
      ring.style.width = d + 'px';
      ring.style.height = d + 'px';
      ring.style.opacity = String(Math.pow(1 - r, 1.4) * 0.95);
      ring.style.borderWidth = Math.max(1.5, 3.5 * (1 - r * 0.6)) + 'px';
    } else {
      ring.style.display = 'none';
    }
  }

  window.__cur = {
    ensure: ensure,
    frame: function (s) {
      if (s && typeof s === 'object') {
        if (typeof s.x === 'number') st.x = s.x;
        if (typeof s.y === 'number') st.y = s.y;
        if (typeof s.press === 'number') st.press = s.press;
        if (typeof s.ripple === 'number') st.ripple = s.ripple;
        if (typeof s.visible === 'boolean') st.visible = s.visible;
      }
      paint();
      return { x: st.x, y: st.y };
    },
    // 真实鼠标事件也跟一下 —— 手写 page.mouse.move 时不必自己喂坐标
    _track: function (e) { st.x = e.clientX; st.y = e.clientY; paint(); },
  };

  document.addEventListener('mousemove', window.__cur._track, true);
  if (document.body) ensure();
  else document.addEventListener('DOMContentLoaded', ensure, { once: true });
}

async function installCursor(ctxOrPage, opts) {
  const o = { kind: (opts && opts.kind) || 'touch', size: (opts && opts.size) || 46 };
  await ctxOrPage.addInitScript(OVERLAY, o);
}

// 在已经打开的页面上补装（addInitScript 只对之后的导航生效）
async function installCursorNow(page, opts) {
  const o = { kind: (opts && opts.kind) || 'touch', size: (opts && opts.size) || 46 };
  await page.evaluate(OVERLAY, o);
}

module.exports = { installCursor, installCursorNow, OVERLAY };
