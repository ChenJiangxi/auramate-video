// actor.js — 按**帧**驱动的页面操作演员：移动光标、点、打字、滚，以及圈重点。
//
// 录屏脚本每截一帧之前调一次 actor.tick(i)，由它把「第 i 帧该是什么样」摆好。
// 所有进度都用帧序号算，不看墙上时间 —— 截一帧要 100–300ms 且不均匀，
// 任何按墙上时间跑的动画（CSS transition、keyboard delay）在成片里都会忽快忽慢。
//
// 动作表（--act 传的 JSON 数组，at 是**视频时间**秒）:
//   {"at":0.4, "do":"tap",   "to":"button:has-text('开始')"}      移过去 + 点一下（最常用）
//   {"at":1.2, "do":"move",  "to":[360,900], "over":0.5}          只移动
//   {"at":1.2, "do":"move",  "to":{"xp":0.5,"yp":0.42}}           按视口比例定位
//   {"at":2.0, "do":"click"}                                      在当前位置点
//   {"at":2.4, "do":"type",  "text":"1995-08-11", "over":0.9}     逐帧把字打出来
//   {"at":4.0, "do":"wheel", "dy":800, "over":1.6}                滚动，摊到这段时间里
//   {"at":7.0, "do":"hide"} / {"do":"show"}                       收起/放出光标
//
// 强调动作 —— 光标解决「有人在操作」，强调解决「该看哪」:
//   {"at":2.0, "do":"spot",  "to":"#kline", "hold":2.4}           除了这块，整屏压暗
//   {"at":2.0, "do":"ring",  "to":".btn",   "hold":1.6}           套个发光的框，不压暗别处
//   {"at":2.0, "do":"mark",  "to":"h2",     "hold":2.0}           记号笔贴着字底扫一条
//   {"at":2.0, "do":"label", "to":"#ganzhi","text":"真太阳时 19:30","hold":2.2}
//   {"at":4.5, "do":"clear"}                                      收掉所有强调
//   {"at":4.5, "do":"clear", "id":"spot"}                         只收暗场（id 也可以是自起的名字）
//
// 强调的公共参数：over 展开时长(默认.35s) · hold 停留时长(不给=留到 clear 或录完) ·
//   out 收起时长(默认.3s) · pad 外扩像素 · r 圆角 · color 主色 · id 自起的名字（给 clear 用）
//   spot 另有 dim(压暗深度，默认.58) · ring 另有 weight(边框粗细) · mark 另有 full(整块盖)
//   label 另有 size(字号) · place("above"/"below")
//
// to 的写法：CSS 选择器（运行时才解析，位置随页面变）/ [x,y] CSS 像素 /
// {xp,yp} 视口比例；强调还认 [x,y,w,h] / {x,y,w,h} / {xp,yp,wp,hp} 这种整块矩形。
// 选择器找不到就跳过这条并打印，不中断录制 —— 录一次好几分钟，
// 不值得为一个选择器全废。
//
// 强调框每帧都重新量一次目标位置 —— 页面还在滚、图片刚加载完撑高了，框都得跟着走，
// 不然旁白说着「看这里」，框已经落在别的元素上了（跟 tap 的落点要现量是同一个理）。
//
// 缓动用 smoothstep(3t²−2t³)，和 lib/motion.sh 的镜头运动同一条曲线：
// 起步和收尾都软，中间快。匀速移动看着像被拖着走，不像手。
'use strict';

const smooth = (t) => (t <= 0 ? 0 : t >= 1 ? 1 : t * t * (3 - 2 * t));
const FX_KINDS = ['spot', 'ring', 'mark', 'label'];

class Actor {
  constructor(page, actions, opts) {
    this.page = page;
    this.fps = opts.fps;
    this.W = opts.w;
    this.H = opts.h;
    this.log = opts.log || (() => {});
    this.acts = (actions || []).slice().sort((a, b) => (a.at || 0) - (b.at || 0));
    this.acts.forEach((a) => { a.__done = false; });
    this.pending = [];          // 运行中派生出来的动作（tap 拆出来的那一下 click）
    // 光标起点：视口正下方外面。第一次 move 就成了「手从下面伸进来」，
    // 比凭空出现在页面中央自然。
    this.cur = { x: opts.w / 2, y: opts.h + 70 };
    this.press = 0;
    this.rippleFrame = -1;      // ≥0 表示水波纹正在放，单位是帧
    this.rippleLen = Math.max(2, Math.round(0.42 * opts.fps));
    // --no-cursor 只是把手指收起来，强调层照画（两者共用同一个叠加层）
    this.visible = opts.cursorVisible !== false;
    this.tween = null;          // {x0,y0,x1,y1,f0,len}
    this.wheel = null;          // {perFrame,f0,len,done}
    this.typing = null;         // {text,i,f0,len}
    this.fx = [];               // 正在画的强调，见 _startFx
    this.fxSeq = 0;
  }

  async _resolve(to) {
    if (Array.isArray(to)) return { x: to[0], y: to[1] };
    if (to && typeof to === 'object') {
      if (typeof to.xp === 'number' || typeof to.yp === 'number') {
        return { x: (to.xp ?? 0.5) * this.W, y: (to.yp ?? 0.5) * this.H };
      }
      if (typeof to.x === 'number') return { x: to.x, y: to.y };
    }
    if (typeof to === 'string') {
      try {
        const box = await this.page.locator(to).first().boundingBox({ timeout: 1500 });
        if (box) {
          const p = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
          // boundingBox 是**视口**坐标：元素被滚出去了就会是负数或超出视口高度。
          // 这时候点下去什么也不会发生，而画面上光标看着好好的 —— 必须喊出来，
          // 不然只能靠事后逐帧看才发现这一下点空了。
          if (p.y < 0 || p.y > this.H || p.x < 0 || p.x > this.W) {
            this.log(`  ! 「${to}」在视口外（x=${p.x.toFixed(0)} y=${p.y.toFixed(0)}），` +
                     `这一下会点空 —— 先加一条 wheel 把它滚进来再点`);
          }
          return p;
        }
      } catch { /* 落到下面报 null */ }
      this.log(`  ! 选择器没命中，跳过这条动作: ${to}`);
      return null;
    }
    return null;
  }

  // 强调要的是**一块矩形**，不是一个点
  async _rect(to, timeout = 1500) {
    if (Array.isArray(to)) {
      if (to.length >= 4) return { x: to[0], y: to[1], w: to[2], h: to[3] };
      this.log('  ! 强调的 to 给了 [x,y]，但强调要的是一块矩形 [x,y,w,h]');
      return null;
    }
    if (to && typeof to === 'object') {
      if (typeof to.w === 'number' && typeof to.x === 'number') {
        return { x: to.x, y: to.y, w: to.w, h: to.h };
      }
      if (typeof to.wp === 'number' || typeof to.hp === 'number') {
        const w = (to.wp ?? 0.8) * this.W, h = (to.hp ?? 0.2) * this.H;
        // xp/yp 当中心，和 move 的写法保持一致
        return { x: (to.xp ?? 0.5) * this.W - w / 2, y: (to.yp ?? 0.5) * this.H - h / 2, w, h };
      }
    }
    if (typeof to === 'string') {
      try {
        const b = await this.page.locator(to).first().boundingBox({ timeout });
        if (b && b.width > 0 && b.height > 0) return { x: b.x, y: b.y, w: b.width, h: b.height };
      } catch { /* 落到下面报 null */ }
      return null;
    }
    this.log('  ! 强调的 to 只认：选择器 / [x,y,w,h] / {x,y,w,h} / {xp,yp,wp,hp}');
    return null;
  }

  async _startFx(a, i) {
    const rect = await this._rect(a.to);
    if (!rect) { this.log(`  ! 强调目标没命中，跳过这条: ${JSON.stringify(a.to)}`); return; }
    // 两块暗场叠在一起 = 互相把对方那块也压暗了。新的一进来，旧的就退场。
    if (a.do === 'spot') this._kill('spot', i);
    const f = {
      id: a.id || `${a.do}${++this.fxSeq}`,
      kind: a.do,
      sel: typeof a.to === 'string' ? a.to : null,
      rect,
      f0: i,
      enter: Math.max(1, Math.round((typeof a.over === 'number' ? a.over : 0.35) * this.fps)),
      out: Math.max(1, Math.round((typeof a.out === 'number' ? a.out : 0.3) * this.fps)),
      hold: typeof a.hold === 'number' ? Math.max(0, Math.round(a.hold * this.fps)) : null,
      dying: null,
      warned: false,
      opts: {
        pad: a.pad, r: a.r, dim: a.dim, color: a.color, weight: a.weight,
        full: a.full, text: a.text, size: a.size, place: a.place,
      },
    };
    if (a.do === 'label' && !a.text) this.log('  ! label 没给 text，气泡会是空的');
    this.fx.push(f);
  }

  // 让匹配的强调开始退场（id 可以是自起的名字，也可以直接写种类）
  _kill(id, i) {
    for (const f of this.fx) {
      if (f.dying !== null) continue;
      if (id && f.id !== id && f.kind !== id) continue;
      f.dying = i;
    }
  }

  async _start(a, i) {
    const over = typeof a.over === 'number' ? a.over : null;
    if (FX_KINDS.includes(a.do)) return this._startFx(a, i);
    switch (a.do) {
      case 'move':
      case 'tap': {
        const p = await this._resolve(a.to);
        if (!p) return;
        const len = Math.max(1, Math.round((over ?? 0.45) * this.fps));
        this.tween = { x0: this.cur.x, y0: this.cur.y, x1: p.x, y1: p.y, f0: i, len };
        if (a.do === 'tap') {
          // 点在**移动结束的那一帧**，不是现在。
          // 放进 pending 而不是 this.acts —— 正在遍历的数组不能边遍历边排序。
          // 带上选择器：落点要在按下的那一刻重新量一次（见 click 分支）。
          this.pending.push({ at: (i + len) / this.fps, do: 'click', to: a.to, __done: false });
        }
        break;
      }
      case 'click': {
        // 落点在**按下的这一刻**重新量。move 开始时量的那个坐标，到落下时可能已经不准了：
        // 页面还在惯性滚、图片刚加载完撑高了、骨架屏换成了真内容 —— 都会让元素挪几十像素。
        // 挪一点点最阴：光标画面上明明压在按钮上，实际擦着边点空，逐帧看都未必看得出来。
        if (a.to) {
          const p = await this._resolve(a.to);
          if (p) { this.cur.x = p.x; this.cur.y = p.y; }
        }
        this.press = 1;
        this.rippleFrame = 0;
        try { await this.page.mouse.click(this.cur.x, this.cur.y, { delay: 30 }); }
        catch (e) { this.log(`  ! 点击失败: ${e.message}`); }
        break;
      }
      case 'type': {
        const text = String(a.text ?? '');
        const len = Math.max(1, Math.round((over ?? Math.max(0.4, text.length * 0.09)) * this.fps));
        this.typing = { text, i: 0, f0: i, len };
        break;
      }
      case 'wheel': {
        const len = Math.max(1, Math.round((over ?? 1.0) * this.fps));
        this.wheel = { perFrame: (a.dy || 0) / len, f0: i, len };
        break;
      }
      case 'clear': this._kill(a.id || null, i); break;
      case 'hide': this.visible = false; break;
      case 'show': this.visible = true; break;
      default: this.log(`  ! 不认识的动作 "${a.do}"`);
    }
  }

  // 每帧重新量一次目标，再算这一帧的展开进度/透明度。退场结束的就丢掉。
  async _tickFx(i) {
    const out = [];
    const live = [];
    for (const f of this.fx) {
      if (f.sel) {
        // 短超时：元素暂时不在（SPA 切页、还在加载）就沿用上一次量到的位置，
        // 不要卡住整帧 —— 一帧卡 1.5s，一条 12 秒的片子就多录两分钟。
        const r = await this._rect(f.sel, 250);
        if (r) f.rect = r;
      }
      const age = i - f.f0;
      let k = smooth(Math.min(1, (age + 1) / f.enter));
      let a = k;
      if (f.dying === null && f.hold !== null && age >= f.enter + f.hold) f.dying = i;
      if (f.dying !== null) {
        const d = (i - f.dying) / f.out;
        k = 1;
        a = 1 - smooth(Math.min(1, d));
        if (d >= 1) continue;              // 退场走完，这一条不再进下一帧
      }
      live.push(f);
      const r = f.rect;
      const offscreen = r.y + r.h < 0 || r.y > this.H || r.x + r.w < 0 || r.x > this.W;
      if (offscreen) {
        if (!f.warned) {
          f.warned = true;
          this.log(`  ! 强调目标「${f.sel || 'rect'}」在视口外，这一段画面上什么都看不见 ——` +
                   ` 先加一条 wheel 把它滚进来`);
        }
        continue;                          // 不画：暗场的洞跑到屏幕外 = 整屏全黑
      }
      // ring 的呼吸：1.2 秒一轮，也按帧算，不用 CSS 动画
      const glow = f.kind === 'ring'
        ? 0.5 + 0.5 * Math.sin((age / (this.fps * 1.2)) * Math.PI * 2)
        : undefined;
      out.push({
        kind: f.kind, x: r.x, y: r.y, w: r.w, h: r.h, k, a, glow,
        pad: f.opts.pad, r: f.opts.r, dim: f.opts.dim, color: f.opts.color,
        weight: f.opts.weight, full: f.opts.full,
        text: f.opts.text, size: f.opts.size, place: f.opts.place,
      });
    }
    this.fx = live;
    // 叠加层按数组顺序画，后面的盖前面的。暗场必须排最前 ——
    // 不然「先 ring 后 spot」的写法会让暗场盖在框上，框被压暗一层，等于白圈。
    out.sort((a, b) => (a.kind === 'spot' ? 0 : 1) - (b.kind === 'spot' ? 0 : 1));
    return out;
  }

  async tick(i) {
    const t = i / this.fps;

    // ① 先把移动走完，再触发动作。顺序反了，点击会用上一帧的坐标 ——
    //    tap 的那一下正好落在「刚要到达但还没到」的位置，点空了还看不出来
    //    （光标画面上明明在按钮上）。这个 bug 只在 tap 起点离目标远时才显形。
    if (this.tween) {
      const k = smooth((i - this.tween.f0) / this.tween.len);
      this.cur.x = this.tween.x0 + (this.tween.x1 - this.tween.x0) * k;
      this.cur.y = this.tween.y0 + (this.tween.y1 - this.tween.y0) * k;
      // 真的把鼠标挪过去，hover 态才会亮
      try { await this.page.mouse.move(this.cur.x, this.cur.y); } catch {}
      if (i - this.tween.f0 >= this.tween.len) this.tween = null;
    }

    // ② 到点的动作。遍历时不动 this.acts，新排的动作先进 pending。
    const due = this.acts.concat(this.pending)
      .filter((a) => !a.__done && (a.at || 0) <= t + 1e-6)
      .sort((x, y) => (x.at || 0) - (y.at || 0));
    for (const a of due) { a.__done = true; await this._start(a, i); }

    if (this.wheel) {
      try { await this.page.mouse.wheel(0, this.wheel.perFrame); } catch {}
      if (i - this.wheel.f0 >= this.wheel.len) this.wheel = null;
    }

    if (this.typing) {
      const k = Math.min(1, (i - this.typing.f0 + 1) / this.typing.len);
      const want = Math.ceil(k * this.typing.text.length);
      if (want > this.typing.i) {
        const chunk = this.typing.text.slice(this.typing.i, want);
        this.typing.i = want;
        try { await this.page.keyboard.type(chunk); } catch {}
      }
      if (this.typing.i >= this.typing.text.length) this.typing = null;
    }

    // 按下的形变只留 2 帧，再久就像一直摁着不放
    if (this.press > 0) this.press = Math.max(0, this.press - 1 / 2);
    let ripple = -1;
    if (this.rippleFrame >= 0) {
      ripple = this.rippleFrame / this.rippleLen;
      this.rippleFrame = ripple >= 1 ? -1 : this.rippleFrame + 1;
    }

    // 强调最后算：这一帧该滚的已经滚完，量到的位置才是截图时的位置
    const fx = await this._tickFx(i);

    const state = { x: this.cur.x, y: this.cur.y, press: this.press, ripple, visible: this.visible, fx };
    try { await this.page.evaluate((s) => window.__cur && window.__cur.frame(s), state); } catch {}
  }
}

module.exports = { Actor, smooth, FX_KINDS };
