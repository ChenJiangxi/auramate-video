// cursor-overlay.js — 给录屏画一个看得见的手指/光标、点按的水波纹，以及**强调层**
// （暗场聚光 / 高亮框 / 记号笔 / 标注气泡）。
//
// 为什么要自己画：Playwright 截图和 recordVideo 都**不含系统光标**。不画的话，
// 页面会自己动、输入框会自己填字，观众看不到是谁在操作 —— 像 bug 不像演示。
//
// 为什么还要强调层：光标只解决「有人在操作」，不解决「该看哪」。一屏产品界面
// 几十个元素，旁白正在说的那一个，观众得自己找 —— 找的这两秒，话已经过去了。
// 竖版更狠：画面缩到手机上，字比按钮还小。所以要么把周围压暗只留一块亮，
// 要么给它套个框、划条线、贴个字。
//
// ⚠ 一条硬规矩：这里所有动画都不许用 CSS animation / transition。
//   截图是逐帧同步取的，每帧的墙上时间间隔并不均匀（一帧要 100–300ms，还会抖），
//   而 CSS 动画按墙上时间跑。两者一混，输出视频里的水波纹就会忽快忽慢。
//   正确做法和音频驱动时间轴同理：**帧序号就是时钟**，每帧显式把状态摆好再截图。
//   所以这里只暴露 `__cur.frame({x,y,press,ripple,fx})`，一切进度由外部按帧算。
//
// 光标两种形态:
//   touch  半透明圆点 + 按下水波纹  ← 默认。录的是移动端布局，观众预期是手指
//   arrow  桌面箭头
//
// 强调四种形态（每帧由外部给矩形和进度，见 lib/actor.js）:
//   spot   暗场聚光：除了这块，整屏压暗   ← 最强，一屏找一个元素时用
//   ring   高亮框：套个发光的框，不压暗别处 ← 次强，周围内容也要看得见时用
//   mark   记号笔：贴着文字底部扫一条      ← 划重点，只对一行字
//   label  标注气泡：元素旁边贴一句话      ← 界面上没写、但旁白在说的信息
//
// 用法（rec-frames.js / rec-page.js 已接好，一般不用直接调）:
//   const { installCursor } = require('./cursor-overlay');
//   await installCursor(context, { kind: 'touch', size: 46 });
//   await page.evaluate(s => window.__cur.frame(s), {
//     x: 360, y: 800, press: 0, ripple: -1,
//     fx: [{ kind: 'spot', x: 40, y: 300, w: 640, h: 260, k: 1, a: 1 }],
//   });

'use strict';

// 这个函数会被序列化后注入页面，**不能引用外部作用域的任何东西**。
function OVERLAY(opts) {
  if (window.__cur) { window.__cur.ensure(); return; }
  const KIND = opts.kind || 'touch';
  const SIZE = opts.size || 46;
  const NS = 'http://www.w3.org/2000/svg';

  const ARROW = 'M3,2 L3,25 L9,19.5 L13,28 L17.5,26 L13.5,17.8 L21,17.5 Z';
  const GOLD = 'rgba(255,209,102,.92)';       // 高亮主色，和片子里的强调色同一支
  let root = null, dot = null, ring = null, fxRoot = null;
  let st = { x: -999, y: -999, press: 0, ripple: -1, visible: true, fx: [] };

  const cl = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);

  function build() {
    root = document.createElement('div');
    root.id = '__cursor_overlay';
    root.setAttribute('data-cursor-overlay', '1');
    root.style.cssText =
      'position:fixed;left:0;top:0;width:0;height:0;margin:0;padding:0;border:0;' +
      'z-index:2147483647;pointer-events:none;';

    // 强调层先挂 —— 后挂的画在上面，手指必须盖在高亮之上，不能被暗场吃掉
    fxRoot = document.createElement('div');
    fxRoot.style.cssText = 'position:fixed;left:0;top:0;width:0;height:0;pointer-events:none;';
    root.appendChild(fxRoot);

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

  // ---------- 强调层 ----------

  function makeNode(kind) {
    const n = document.createElement('div');
    n.__kind = kind;
    n.style.cssText = 'position:fixed;pointer-events:none;box-sizing:border-box;' +
      'will-change:transform,opacity;';
    if (kind === 'label') {
      // 气泡本体 + 一个旋转 45° 的小尖角。尖角单独放，才能指向元素中心而不是气泡中心
      n.style.cssText +=
        'padding:7px 14px;border-radius:999px;white-space:nowrap;' +
        'background:rgba(17,18,24,.90);color:#fff;border:1px solid rgba(255,255,255,.20);' +
        'box-shadow:0 8px 24px rgba(0,0,0,.5);font-weight:600;letter-spacing:.02em;' +
        'font-family:-apple-system,"PingFang SC","Noto Sans CJK SC",sans-serif;line-height:1.3;';
      const span = document.createElement('span');
      n.appendChild(span);
      n.__txt = span;
      const tip = document.createElement('div');
      tip.style.cssText = 'position:absolute;width:11px;height:11px;' +
        'background:rgba(17,18,24,.90);border-right:1px solid rgba(255,255,255,.20);' +
        'border-bottom:1px solid rgba(255,255,255,.20);transform:rotate(45deg);';
      n.appendChild(tip);
      n.__tip = tip;
    }
    return n;
  }

  function paintFx() {
    const list = st.fx || [];
    while (fxRoot.children.length < list.length) fxRoot.appendChild(makeNode('spot'));
    for (let i = 0; i < fxRoot.children.length; i++) {
      let node = fxRoot.children[i];
      const f = list[i];
      if (!f || !f.kind) { node.style.display = 'none'; continue; }
      if (node.__kind !== f.kind) {                 // 类型换了就换节点，样式串不混着改
        const fresh = makeNode(f.kind);
        fxRoot.replaceChild(fresh, node);
        node = fresh;
      }
      const a = cl(f.a === undefined ? 1 : f.a);
      const k = cl(f.k === undefined ? 1 : f.k);
      if (a <= 0.004 || !(f.w > 0) || !(f.h > 0)) { node.style.display = 'none'; continue; }
      node.style.display = 'block';
      node.style.opacity = String(a);               // 透明度统一走 opacity —— box-shadow 也跟着淡
      if (f.kind === 'spot') paintSpot(node, f, k);
      else if (f.kind === 'ring') paintRing(node, f, k);
      else if (f.kind === 'mark') paintMark(node, f, k);
      else if (f.kind === 'label') paintLabel(node, f, k);
      else node.style.display = 'none';
    }
  }

  // 进场时框从外面收进来：一上来就贴死，看着像硬切；收一下，眼睛会跟着走
  function grown(f, k) {
    const pad = f.pad === undefined ? 8 : f.pad;
    const g = (1 - k) * 26;
    return { x: f.x - pad - g, y: f.y - pad - g, w: f.w + 2 * (pad + g), h: f.h + 2 * (pad + g),
             r: (f.r === undefined ? 14 : f.r) + g * 0.5 };
  }

  // 暗场：靠一个巨大的外扩阴影把整屏压暗，中间这块留亮
  function paintSpot(n, f, k) {
    const b = grown(f, k);
    const dim = f.dim === undefined ? 0.58 : f.dim;
    n.style.left = b.x + 'px'; n.style.top = b.y + 'px';
    n.style.width = b.w + 'px'; n.style.height = b.h + 'px';
    n.style.borderRadius = b.r + 'px';
    n.style.background = 'transparent';
    n.style.border = '1px solid rgba(255,255,255,.16)';
    n.style.boxShadow = '0 0 0 9999px rgba(0,0,0,' + dim.toFixed(3) + ')';
  }

  // 高亮框：不压暗别处，只把这块框起来。glow 由外部按帧给（呼吸感）
  function paintRing(n, f, k) {
    const b = grown(f, k);
    const col = f.color || GOLD;
    const g = cl(f.glow === undefined ? 0.5 : f.glow);
    n.style.left = b.x + 'px'; n.style.top = b.y + 'px';
    n.style.width = b.w + 'px'; n.style.height = b.h + 'px';
    n.style.borderRadius = b.r + 'px';
    n.style.background = 'transparent';
    n.style.border = (f.weight || 3) + 'px solid ' + col;
    n.style.boxShadow = '0 0 ' + (9 + 15 * g).toFixed(1) + 'px ' + col +
      ', inset 0 0 ' + (6 + 10 * g).toFixed(1) + 'px rgba(255,209,102,.28)' +
      ', 0 0 0 1px rgba(0,0,0,.35)';
  }

  // 记号笔：贴着文字**底部**扫过去，只盖下面一截。
  // 整块盖会糊住字 —— 观众看产品片是来读界面的，字糊了这一拍就白录。
  function paintMark(n, f, k) {
    const bh = Math.max(6, f.h * (f.full ? 1 : 0.42));
    n.style.left = (f.x - 4) + 'px';
    n.style.top = (f.y + f.h - bh) + 'px';
    n.style.width = ((f.w + 8) * k) + 'px';       // k 就是笔扫过去的进度
    n.style.height = bh + 'px';
    n.style.borderRadius = '5px';
    n.style.border = '0';
    n.style.boxShadow = 'none';
    n.style.background = f.color || 'rgba(255,209,102,.42)';
  }

  // 标注气泡：默认贴在元素上方，上面放不下自动翻到下面
  function paintLabel(n, f, k) {
    const txt = f.text === undefined ? '' : String(f.text);
    n.style.fontSize = (f.size || 22) + 'px';
    if (n.__txt.textContent !== txt) n.__txt.textContent = txt;
    const vw = window.innerWidth, vh = window.innerHeight;
    const bw = n.offsetWidth, bh = n.offsetHeight;
    const gap = 14, rise = (1 - k) * 10;
    let above = f.place !== 'below';
    if (above && f.y - gap - bh < 6) above = false;          // 上面顶到头了就翻下去
    if (!above && f.y + f.h + gap + bh > vh - 6) above = true;
    const cxT = f.x + f.w / 2;
    const left = Math.max(8, Math.min(vw - 8 - bw, cxT - bw / 2));
    const top = above ? (f.y - gap - bh + rise) : (f.y + f.h + gap - rise);
    n.style.left = left + 'px';
    n.style.top = top + 'px';
    const tx = Math.max(12, Math.min(bw - 23, cxT - left - 5.5));   // 尖角指元素中心，不是气泡中心
    n.__tip.style.left = tx + 'px';
    n.__tip.style.top = above ? (bh - 6) + 'px' : '-6px';
    n.__tip.style.transform = above ? 'rotate(45deg)' : 'rotate(225deg)';
  }

  function paint() {
    if (!ensure()) return;
    paintFx();
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
        if (Array.isArray(s.fx)) st.fx = s.fx;      // 没给就沿用上一帧，和其它字段一个规矩
      }
      paint();
      return { x: st.x, y: st.y, fx: st.fx.length };
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
