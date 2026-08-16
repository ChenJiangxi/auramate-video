#!/usr/bin/env bash
# validate.sh — repo 自检。每轮改动后必须跑，全绿才能 push。
#   1. skill 结构 + frontmatter（name/description，name 必须等于目录名）
#   2. 文档里引用的 repo 内路径不能死链
#   3. 所有 .sh 语法可解析且可执行；.py 可编译
#   4. **真的跑一遍 examples/hello-vertical 全链路**，ffprobe 校验产物
#   5. 泄密扫描：不许出现真实密钥形态的字符串
#
# 用法: tests/validate.sh [--skip-render]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SKIP_RENDER=0
[ "${1:-}" = "--skip-render" ] && SKIP_RENDER=1

fail=0
sec(){ printf '\n== %s\n' "$1"; }
ok(){  printf '  ✓ %s\n' "$1"; }
bad(){ printf '  ✗ %s\n' "$1"; fail=1; }

# ---------------------------------------------------------------- 1 + 2 + 5
sec "skill 结构 / 死链 / 泄密扫描"
/usr/bin/env python3 - "$ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]
bad = []

# --- skills 结构 ---
sk = os.path.join(root, 'skills')
names = sorted(d for d in os.listdir(sk) if os.path.isdir(os.path.join(sk, d))) if os.path.isdir(sk) else []
if not names:
    bad.append('skills/ 下没有任何 skill')
for d in names:
    p = os.path.join(sk, d, 'SKILL.md')
    if not os.path.exists(p):
        bad.append(f'{d}: 缺 SKILL.md'); continue
    txt = open(p, encoding='utf-8').read()
    if not txt.startswith('---\n'):
        bad.append(f'{d}: SKILL.md 没有 frontmatter'); continue
    fm = txt.split('---\n', 2)[1]
    m_name = re.search(r'^name:\s*(\S+)\s*$', fm, re.M)
    m_desc = re.search(r'^description:\s*(.+)$', fm, re.M)
    if not m_name: bad.append(f'{d}: frontmatter 缺 name')
    elif m_name.group(1) != d: bad.append(f'{d}: frontmatter name={m_name.group(1)} ≠ 目录名')
    if not m_desc: bad.append(f'{d}: frontmatter 缺 description')
    elif len(m_desc.group(1).strip()) < 20: bad.append(f'{d}: description 太短，agent 路由不到')
print(f'  skills: {len(names)} 个 -> {", ".join(names)}')

# --- 死链：文档里出现的 repo 内路径 ---
# PROGRESS.md 是路线图，列的是「还没建的东西」，本来就该指向不存在的路径 → 豁免
LINK_EXEMPT = {'PROGRESS.md'}
PATH_RE = re.compile(r'`((?:skills|lib|tests|examples|assets|references)/[A-Za-z0-9._/\-]+)`')
checked = 0
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in ('.git', 'work', 'node_modules', 'subs', 'audio', 'footage')]
    for fn in filenames:
        if not fn.endswith('.md') or fn in LINK_EXEMPT:
            continue
        fp = os.path.join(dirpath, fn)
        for ref in set(PATH_RE.findall(open(fp, encoding='utf-8').read())):
            checked += 1
            target = os.path.join(root, ref.rstrip('/'))
            if not os.path.exists(target):
                bad.append(f'死链 {os.path.relpath(fp, root)} -> {ref}')
print(f'  内部路径引用: {checked} 处')

# --- 泄密扫描 ---
LEAK = [
    (re.compile(r'\bsk-[A-Za-z0-9_\-]{16,}'),        'OpenAI 形态 key'),
    (re.compile(r'\bgh[pousr]_[A-Za-z0-9]{20,}'),    'GitHub token'),
    (re.compile(r'eyJ[A-Za-z0-9_\-]{20,}\.[A-Za-z0-9_\-]{20,}'), 'JWT'),
    (re.compile(r'-----BEGIN [A-Z ]*PRIVATE KEY-----'), '私钥'),
    (re.compile(r'(?i)\b(password|passwd|api[_-]?key|secret)\s*[=:]\s*["\']?[A-Za-z0-9!@#$%^&*_\-]{12,}'), '疑似硬编码凭据'),
]
ALLOW = ('<', '${', 'YOUR_', 'xxx', 'XXX', '占位', 'process.env')
scanned = 0
for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in ('.git', 'work', 'node_modules')]
    for fn in filenames:
        fp = os.path.join(dirpath, fn)
        if os.path.getsize(fp) > 512_000: continue
        try: txt = open(fp, encoding='utf-8').read()
        except Exception: continue
        scanned += 1
        for rx, label in LEAK:
            for m in rx.finditer(txt):
                s = m.group(0)
                if any(a in s for a in ALLOW): continue
                bad.append(f'疑似泄密 [{label}] {os.path.relpath(fp, root)}: {s[:24]}…')
print(f'  泄密扫描: {scanned} 个文件')

for b in bad: print('  ✗ ' + b)
sys.exit(1 if bad else 0)
PY
[ $? -eq 0 ] && ok "结构 / 链接 / 泄密 全部通过" || fail=1

# ---------------------------------------------------------------- 2.5
sec "一致性（孤儿脚本 / 路由 / README 覆盖 / 旧说法复活）"
if /usr/bin/python3 tests/check-consistency.py "$ROOT" >/tmp/av-cons.log 2>&1; then
  ok "$(tail -1 /tmp/av-cons.log | sed 's/^ *//')"
else
  bad "一致性检查失败"; grep '✗' /tmp/av-cons.log | sed 's/^/  /'
fi

# ---------------------------------------------------------------- 3
sec "脚本可执行性 + 语法"
while IFS= read -r f; do
  [ -x "$f" ] || { bad "$f 没有执行位（chmod +x）"; continue; }
  bash -n "$f" 2>/dev/null || { bad "$f bash 语法错误"; continue; }
  # 真实踩过：不加花括号的变量名后面紧跟全角括号时，bash 把全角字节吞进变量名
  # → unbound variable。变量后紧跟非 ASCII 字符时必须写成 ${VAR} 形式。
  if LC_ALL=C grep -qE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' "$f" 2>/dev/null; then
    bad "$f 有 \$VAR 后面紧跟中文/全角字符 —— 改成 \${VAR}"; continue
  fi
  ok "$(basename "$f")"
done < <(find lib tests examples install.sh -name '*.sh' -not -path '*/work/*' 2>/dev/null | sort)

while IFS= read -r f; do
  /usr/bin/env python3 -m py_compile "$f" 2>/dev/null && ok "$(basename "$f")" || bad "$f python 语法错误"
done < <(find lib tests -name '*.py' 2>/dev/null | sort)
rm -rf lib/__pycache__ tests/__pycache__ 2>/dev/null

while IFS= read -r f; do
  node --check "$f" 2>/dev/null && ok "$(basename "$f")" || bad "$f node 语法错误"
done < <(find lib -name '*.mjs' -o -name '*.js' 2>/dev/null | sort)

# ---------------------------------------------------------------- 3.2
sec "install 三种 target"
IT="$ROOT/tests/fixtures/inst"; rm -rf "$IT"; mkdir -p "$IT/claude" "$IT/codex"
if "$ROOT/install.sh" claude "$IT/claude" >/dev/null 2>&1 \
   && [ -d "$IT/claude/.claude/skills/video-master" ]; then
  ok "claude target：skills 复制到 .claude/skills/"
else bad "claude target 失败"; fi
if "$ROOT/install.sh" codex "$IT/codex" >/dev/null 2>&1 && [ -f "$IT/codex/AGENTS.md" ]; then
  if grep -q '__REPO__' "$IT/codex/AGENTS.md"; then bad "AGENTS.md 里还有没替换的占位符"
  else ok "codex target：AGENTS.md 已生成且路径已替换"; fi
else bad "codex target 失败"; fi
if "$ROOT/install.sh" bundle "$IT/b.md" >/dev/null 2>&1 && [ -s "$IT/b.md" ]; then
  nb=$(grep -c '^# ' "$IT/b.md")
  [ "$nb" -ge 13 ] && ok "bundle target：单文件含 $nb 个标题块" || bad "bundle 只有 $nb 个块，skill 没拼全"
else bad "bundle target 失败"; fi
rm -rf "$IT"

# ---------------------------------------------------------------- 3.3
if [ "$SKIP_RENDER" = 1 ]; then
  sec "fit-vertical（已跳过 --skip-render）"
else
sec "fit-vertical 各画幅"
FX="$ROOT/tests/fixtures/fit"; rm -rf "$FX"; mkdir -p "$FX"
# 造出真实素材库里出现过的几类画幅：FHD 16:9 / 低清 16:9 / 4:3 / 竖版 9:16
for spec in "1920x1080 fhd" "640x360 low169" "640x480 r43" "360x640 vert"; do
  set -- $spec
  ffmpeg -nostdin -y -v error -f lavfi -i "testsrc2=size=$1:rate=30:duration=6" \
    -c:v libx264 -crf 24 -pix_fmt yuv420p "$FX/$2.mp4" 2>/dev/null
done
fitfail=0
for n in fhd low169 r43 vert; do
  if "$ROOT/lib/fit-vertical.sh" "$FX/$n.mp4" "$FX/out-$n.mp4" --dur 2 --ss 1 >/tmp/av-fit-$n.log 2>&1; then
    w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$FX/out-$n.mp4")
    h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$FX/out-$n.mp4")
    d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$FX/out-$n.mp4")
    a=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$FX/out-$n.mp4")
    m=$(awk '/mode=/{print $1}' /tmp/av-fit-$n.log | head -1)
    if [ "$w" = 1080 ] && [ "$h" = 1920 ] && [ -z "$a" ] \
       && awk -v d="$d" 'BEGIN{exit !(d>1.8 && d<2.2)}'; then
      ok "$n → 1080×1920 / ${d}s / 无音轨 / $(sed -n 's/.*\(mode=[a-z]*\).*/\1/p' /tmp/av-fit-$n.log | head -1)"
    else bad "$n → ${w}×${h} / ${d}s / audio=${a:-none}"; fitfail=1; fi
  else bad "$n fit-vertical 失败"; sed -n '1,10p' /tmp/av-fit-$n.log; fitfail=1; fi
done
# 素材不够长必须被拦住（这是最常见的翻车）
if "$ROOT/lib/fit-vertical.sh" "$FX/fhd.mp4" "$FX/out-toolong.mp4" --dur 30 >/tmp/av-fit-long.log 2>&1; then
  bad "素材不够长没被拦住"
else
  grep -q '素材不够长' /tmp/av-fit-long.log && ok "素材不够长被拦下并给出还差多少" || bad "报错信息不对"
fi
rm -rf "$FX"
fi

# ---------------------------------------------------------------- 3.34
if [ "$SKIP_RENDER" = 1 ]; then
  sec "镜头运动（已跳过 --skip-render）"
else
sec "镜头运动 motion.sh"
MX="$ROOT/tests/fixtures/mo"; rm -rf "$MX"; mkdir -p "$MX"
ffmpeg -nostdin -y -v error -f lavfi -i "testsrc2=size=720x1280:rate=30:duration=8" \
  -c:v libx264 -crf 24 -pix_fmt yuv420p "$MX/src.mp4" 2>/dev/null
mofail=0
for m in "punch-in --to 300:400:200:300" "pull-out --from 300:400:200:300" \
         "pan --from 720:1280:0:0 --to 300:400:200:600" "kenburns" "hold --zoom 1.4"; do
  set -- $m; name="$1"
  if "$ROOT/lib/motion.sh" "$MX/src.mp4" "$MX/$name.mp4" --dur 2 --ss 1 --move $m >/tmp/av-mo.log 2>&1; then
    w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$MX/$name.mp4")
    h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$MX/$name.mp4")
    [ "$w" = 1080 ] && [ "$h" = 1920 ] || { bad "motion $name → ${w}×${h}"; mofail=1; }
  else bad "motion $name 失败"; sed -n '1,6p' /tmp/av-mo.log; mofail=1; fi
done
[ "$mofail" = 0 ] && ok "五种运动都出 1080×1920"
# 真的在动：首尾两帧必须不同（不动的话说明表达式没生效）
ffmpeg -v error -y -ss 0.1 -i "$MX/punch-in.mp4" -frames:v 1 "$MX/a.png" 2>/dev/null
ffmpeg -v error -y -ss 1.9 -i "$MX/punch-in.mp4" -frames:v 1 "$MX/b.png" 2>/dev/null
sa=$(stat -f%z "$MX/a.png" 2>/dev/null || stat -c%s "$MX/a.png")
sb=$(stat -f%z "$MX/b.png" 2>/dev/null || stat -c%s "$MX/b.png")
[ "$sa" != "$sb" ] && ok "punch-in 首尾帧不同（镜头确实在动）" || bad "首尾帧一样，运动没生效"
# 接进管线：shots.tsv 用 motion 编码器
printf 'c01\tmotion\t%s\t1\t--move punch-in --to 300:400:200:300\n' "$MX/src.mp4" > "$MX/shots.tsv"
printf '[{"name":"c01","text":"测试一句口播。"}]\n' > "$MX/clips.json"
"$ROOT/lib/make-placeholders.sh" "$MX" >/dev/null 2>&1
if "$ROOT/lib/build-vertical.sh" --project "$MX" --shots "$MX/shots.tsv" --out "$MX/o.mp4" >/tmp/av-mo2.log 2>&1; then
  ok "shots.tsv 的 motion 编码器接通了"
else bad "motion 编码器在管线里失败"; sed -n '1,10p' /tmp/av-mo2.log; fi

# --dry-run 只算框不渲（check-motion.py 靠它，别让它退化成真渲染）
if "$ROOT/lib/motion.sh" "$MX/src.mp4" "$MX/never.mp4" --dur 2 --ss 1 \
     --move pan --from 720:1280:0:0 --to 300:400:200:600 --dry-run 2>/dev/null | grep -q '^BOX '; then
  [ -f "$MX/never.mp4" ] && bad "--dry-run 居然真渲了文件" || ok "motion --dry-run 只报框不出文件"
else bad "--dry-run 没打印 BOX 行"; fi

# --lead：开头 N 秒定住，路径只跑剩下的。转场那 0.22s 不许把镜头时序带偏。
"$ROOT/lib/motion.sh" "$MX/src.mp4" "$MX/nolead.mp4" --dur 2.0 --ss 1 \
  --move pan --from 720:1280:0:0 --to 300:400:200:600 >/dev/null 2>&1
# lead 取 0.2s = 整 6 帧。非整帧的话源会被采样在两帧之间，两版差半帧，
# 测出来永远不为零 —— build-vertical 里的转场时长也因此取整到帧。
"$ROOT/lib/motion.sh" "$MX/src.mp4" "$MX/lead.mp4" --dur 2.2 --ss 0.8 --lead 0.2 \
  --move pan --from 720:1280:0:0 --to 300:400:200:600 >/dev/null 2>&1
# 加了 lead 的那条整体后移 0.2s，所以要错开 0.2s 比 —— 对齐了就该几乎一样
dl=$(/usr/bin/python3 "$ROOT/tests/cmp-frame.py" "$MX/nolead.mp4" "$MX/lead.mp4" 0.90 1.10 2>/dev/null || echo 999)
# 反证：不错开地比，必须明显不同，否则说明这条测试根本没测到东西
dn=$(/usr/bin/python3 "$ROOT/tests/cmp-frame.py" "$MX/nolead.mp4" "$MX/lead.mp4" 0.90 0.90 2>/dev/null || echo 0)
if awk -v a="$dl" -v b="$dn" 'BEGIN{exit !(a<4 && b>a+4)}'; then
  ok "--lead 让加长后的镜头时序和原来对齐（错开比 ${dl}，不错开比 ${dn}）"
else bad "--lead 没对齐：错开比 ${dl} / 不错开比 ${dn}"; fi

# check-motion.py：整片镜头单一必须被抓出来
printf 'c01\tmotion\t%s\t0\t--move locate --to 300:400:200:300\n' "$MX/src.mp4"  > "$MX/same.tsv"
printf 'c02\tmotion\t%s\t0\t--move locate --to 300:400:220:320\n' "$MX/src.mp4" >> "$MX/same.tsv"
printf 'c03\tmotion\t%s\t0\t--move locate --to 300:400:240:340\n' "$MX/src.mp4" >> "$MX/same.tsv"
printf 'c04\tmotion\t%s\t0\t--move locate --to 300:400:260:360\n' "$MX/src.mp4" >> "$MX/same.tsv"
if /usr/bin/python3 "$ROOT/lib/check-motion.py" --project "$MX" --shots "$MX/same.tsv" >/tmp/av-cm1.log 2>&1; then
  bad "四拍全从全屏推进去，check-motion 竟然放行"
else
  grep -q '全屏' /tmp/av-cm1.log && ok "check-motion 抓住「每拍都从全屏推进去」" \
    || { bad "check-motion 报的不是全屏起手"; sed -n '/✗/p' /tmp/av-cm1.log; }
fi
# 有变化的一组必须放行（不能误报）
printf 'c01\tmotion\t%s\t0\t--move pan --from 720:1280:0:0 --to 400:520:160:400\n' "$MX/src.mp4"  > "$MX/vary.tsv"
printf 'c02\tmotion\t%s\t0\t--move pan --from 400:520:160:400 --to 260:340:420:700\n' "$MX/src.mp4" >> "$MX/vary.tsv"
printf 'c03\tmotion\t%s\t0\t--move pan --from 260:340:420:700 --to 640:1140:40:70\n' "$MX/src.mp4" >> "$MX/vary.tsv"
printf 'c04\tmotion\t%s\t0\t--move pan --from 300:400:60:500 --to 300:400:420:500\n' "$MX/src.mp4" >> "$MX/vary.tsv"
/usr/bin/python3 "$ROOT/lib/check-motion.py" --project "$MX" --shots "$MX/vary.tsv" >/tmp/av-cm2.log 2>&1 \
  && ok "推-拉-横移混着走的一组放行（不误报）" \
  || { bad "check-motion 误报"; sed -n '/✗/p' /tmp/av-cm2.log; }
rm -rf "$MX"
fi


# ---------------------------------------------------------------- 3.3
if [ "$SKIP_RENDER" = 1 ]; then
  sec "转场（已跳过 --skip-render）"
else
sec "转场：不许偷偷动时间轴"
bash "$ROOT/tests/transitions-test.sh" >/tmp/av-trans.log 2>&1 || fail=1
cat /tmp/av-trans.log
grep -q '✗' /tmp/av-trans.log && fail=1
fi

# ---------------------------------------------------------------- 3.32
if [ "$SKIP_RENDER" = 1 ] || ! node -e "require('playwright')" 2>/dev/null; then
  sec "光标可视化（已跳过：--skip-render 或无 playwright）"
else
sec "光标可视化 + 动作表"
node "$ROOT/tests/cursor-test.js" >/tmp/av-cursor.log 2>&1 || fail=1
cat /tmp/av-cursor.log
grep -q '✗' /tmp/av-cursor.log && fail=1
# 强调层：暗场 / 高亮框 / 记号笔 / 标注气泡（光标说明「有人在操作」，强调说明「该看哪」）
node "$ROOT/tests/highlight-test.js" >/tmp/av-hl.log 2>&1 || fail=1
cat /tmp/av-hl.log
grep -q '✗' /tmp/av-hl.log && fail=1
# 端到端：rec-frames.js --cursor --act 真能出片（上面测的是模块，这里测 CLI 接线）
RC="$ROOT/tests/fixtures/pcur"; rm -rf "$RC"; mkdir -p "$RC"
if node "$ROOT/lib/rec-frames.js" --url "file://$ROOT/tests/fixtures/page/index.html" \
     --out "$RC/act.mp4" --w 720 --h 1280 --dsf 1 --fps 8 --secs 3 \
     --act "$ROOT/tests/fixtures/page/actions.json" >/tmp/av-rc.log 2>&1; then
  grep -q '光标 touch' /tmp/av-rc.log \
    && ok "给了 --act 会自动开光标（不然页面像自己在动）" || bad "--act 没有自动开光标"
  grep -q '强调 [0-9]* 处' /tmp/av-rc.log \
    && ok "动作表里的强调被 CLI 认出来了" || bad "CLI 没识别动作表里的强调"
  w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$RC/act.mp4")
  [ "$w" = 720 ] && ok "rec-frames --cursor --act 出片 ${w}px" || bad "录屏出片尺寸不对: $w"
else bad "rec-frames --act 失败"; sed -n '1,15p' /tmp/av-rc.log; fi
# --no-cursor 只收手指，强调层必须还在（两者共用一个叠加层，早期一关就全没了）
if node "$ROOT/lib/rec-frames.js" --url "file://$ROOT/tests/fixtures/page/index.html" \
     --out "$RC/nc.mp4" --w 720 --h 1280 --dsf 1 --fps 8 --secs 2 --no-cursor \
     --act "$ROOT/tests/fixtures/page/actions.json" >/tmp/av-nc.log 2>&1; then
  grep -q '光标 touch' /tmp/av-nc.log && bad "--no-cursor 却还画了手指" \
    || ok "--no-cursor 收起手指"
  [ -f "$RC/nc.mp4" ] && ok "--no-cursor + 强调仍然出片" || bad "--no-cursor 没出片"
else bad "rec-frames --no-cursor --act 失败"; sed -n '1,15p' /tmp/av-nc.log; fi
rm -rf "$RC"
fi

# ---------------------------------------------------------------- 3.35
if [ "$SKIP_RENDER" = 1 ]; then
  sec "产品录屏工具（已跳过 --skip-render）"
else
sec "产品录屏工具"
PX="$ROOT/tests/fixtures/pd"; rm -rf "$PX"; mkdir -p "$PX"
# 假录屏：中间一列内容 + 两侧黑边（模拟真实录屏的居中列）
ffmpeg -nostdin -y -v error -f lavfi -i "color=c=black:s=1440x2560:r=30:d=6" \
  -f lavfi -i "testsrc2=size=900x2000:rate=30:duration=6" \
  -filter_complex "[0:v][1:v]overlay=(W-w)/2:(H-h)/2" \
  -c:v libx264 -crf 24 -pix_fmt yuv420p "$PX/rec.mp4" 2>/dev/null

if /usr/bin/python3 "$ROOT/lib/browser-chrome.py" --url example.com --path " / app" \
     --out "$PX/chrome.png" --w 1920 --h 120 >/tmp/av-chrome.log 2>&1; then
  cw=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$PX/chrome.png")
  ch=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$PX/chrome.png")
  [ "$cw" = 1920 ] && [ "$ch" = 120 ] && ok "browser-chrome 出图 ${cw}×${ch}" || bad "chrome 尺寸 ${cw}×${ch}"
else bad "browser-chrome.py 失败"; sed -n '1,10p' /tmp/av-chrome.log; fi

for m in "--auto" "--zoom 1.5 --cy 0.45" "--crop 900:1600:270:400"; do
  o="$PX/zc.mp4"
  if "$ROOT/lib/zoom-crop.sh" "$PX/rec.mp4" "$o" --dur 2 --ss 1 $m >/tmp/av-zc.log 2>&1; then
    w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$o")
    h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$o")
    a=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$o")
    [ "$w" = 1080 ] && [ "$h" = 1920 ] && [ -z "$a" ] \
      && ok "zoom-crop ${m} → 1080×1920 无音轨" || bad "zoom-crop ${m} → ${w}×${h} audio=${a:-none}"
  else bad "zoom-crop ${m} 失败"; sed -n '1,8p' /tmp/av-zc.log; fi
done
# --auto 在满帧素材上必须明确提示「没黑边可裁」
ffmpeg -nostdin -y -v error -f lavfi -i "testsrc2=size=720x1280:rate=30:duration=4" \
  -c:v libx264 -crf 24 -pix_fmt yuv420p "$PX/full.mp4" 2>/dev/null
"$ROOT/lib/zoom-crop.sh" "$PX/full.mp4" "$PX/zc2.mp4" --dur 2 --auto >/tmp/av-zc2.log 2>&1 || true
grep -q '没有黑边可裁' /tmp/av-zc2.log && ok "--auto 在满帧素材上给出正确提示" || bad "--auto 提示缺失"

# --grid 出网格样帧
"$ROOT/lib/zoom-crop.sh" "$PX/rec.mp4" "$PX/g.mp4" --ss 1 --grid >/tmp/av-grid.log 2>&1 \
  && [ -f "$PX/g.grid.png" ] && ok "--grid 导出网格样帧" || bad "--grid 失败"

if "$ROOT/lib/wrap-chrome.sh" "$PX/rec.mp4" "$PX/wrap.mp4" --chrome "$PX/chrome.png" \
     --dur 2 --ss 1 >/tmp/av-wrap.log 2>&1; then
  w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$PX/wrap.mp4")
  h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$PX/wrap.mp4")
  [ "$w" = 1920 ] && [ "$h" = 1080 ] && ok "wrap-chrome → 1920×1080（壳 120 + 内容 960）" \
    || bad "wrap-chrome → ${w}×${h}"
else bad "wrap-chrome 失败"; sed -n '1,10p' /tmp/av-wrap.log; fi
# 素材不够长：默认必须报错，--freeze 必须补足
if "$ROOT/lib/wrap-chrome.sh" "$PX/rec.mp4" "$PX/w2.mp4" --chrome "$PX/chrome.png" --dur 20 >/tmp/av-w2.log 2>&1; then
  bad "素材不够长没被拦住"
else grep -q '素材不够长' /tmp/av-w2.log && ok "素材不够长被拦下" || bad "报错信息不对"; fi
if "$ROOT/lib/wrap-chrome.sh" "$PX/rec.mp4" "$PX/w3.mp4" --chrome "$PX/chrome.png" --dur 20 --freeze >/tmp/av-w3.log 2>&1; then
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$PX/w3.mp4")
  awk -v d="$d" 'BEGIN{exit !(d>19.5 && d<20.5)}' && ok "--freeze 冻结末帧补到 ${d}s" || bad "--freeze 后时长 ${d}s"
else bad "--freeze 失败"; sed -n '1,10p' /tmp/av-w3.log; fi
rm -rf "$PX"
fi

# ---------------------------------------------------------------- 3.37
if [ "$SKIP_RENDER" = 1 ]; then
  sec "卡模板 / storyboard（已跳过 --skip-render）"
else
sec "卡模板 / storyboard"
SX="$ROOT/tests/fixtures/storyboard"
rm -rf "$SX/work" "$SX/html" "$SX/shots.tsv" "$SX/one.webm" "$SX/one.png"
# 每个模板都要能被 storyboard.json 引到（防模板改名后 fixture 失联）
missing=""
for t in $(/usr/bin/env python3 -c '
import json,sys
print(" ".join(sorted({b["template"] for b in json.load(open(sys.argv[1]))["beats"]})))' "$SX/storyboard.json"); do
  [ -f "$ROOT/skills/html-motion-cards/templates/$t.html" ] || missing="$missing $t"
done
[ -z "$missing" ] && ok "fixture 引用的模板都存在" || bad "缺模板:$missing"

if node "$ROOT/lib/storyboard.js" --project "$SX" --no-render >/tmp/av-sb0.log 2>&1; then
  grep -q '还有没填的占位符' /tmp/av-sb0.log && bad "模板有没填的占位符" || ok "模板填充完整（无残留占位符）"
  [ -f "$SX/shots.tsv" ] && [ "$(wc -l < "$SX/shots.tsv" | tr -d ' ')" = 5 ] \
    && ok "shots.tsv 5 行，可直接喂 build-vertical" || bad "shots.tsv 行数不对"
else bad "storyboard --no-render 失败"; sed -n '1,10p' /tmp/av-sb0.log; fi

if node -e "require('playwright')" 2>/dev/null; then
  if node "$ROOT/lib/storyboard.js" --project "$SX" >/tmp/av-sb1.log 2>&1; then
    n=0; okn=0
    for f in "$SX"/html/beats/*.webm; do
      n=$((n+1))
      w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$f")
      h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$f")
      d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")
      # 卡必须 >= 请求时长，否则 build 时会黑屏
      [ "$w" = 1080 ] && [ "$h" = 1920 ] && awk -v d="$d" 'BEGIN{exit !(d>=2.0)}' && okn=$((okn+1))
    done
    [ "$n" = 5 ] && [ "$okn" = 5 ] && ok "5 张卡全部渲成 1080×1920 且不短于请求时长" \
      || bad "渲染结果 $okn/$n 合格"
    # 单张卡渲染（storyboard 走的是批量路径，这条脚本单独跑一遍才算被覆盖）
    ONE=$(ls "$SX"/work/cards/*.html 2>/dev/null | head -1)
    if [ -n "$ONE" ]; then
      if node "$ROOT/lib/render-card.js" --html "$ONE" --out "$SX/one.webm" --duration 2 >/tmp/av-rc1.log 2>&1 \
         && node "$ROOT/lib/render-card.js" --html "$ONE" --out "$SX/one.png" --png >/tmp/av-rc2.log 2>&1; then
        cw=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$SX/one.webm")
        cd_=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SX/one.webm")
        pw=$(/usr/bin/python3 -c "from PIL import Image;print(Image.open('$SX/one.png').size[0])" 2>/dev/null)
        [ "$cw" = 1080 ] && awk -v d="$cd_" 'BEGIN{exit !(d>=2.0)}' \
          && ok "render-card 单张：webm ${cw}px / ${cd_}s（不短于请求）" \
          || bad "render-card webm 不合格：${cw}px / ${cd_}s"
        [ "${pw:-0}" -ge 1080 ] && ok "render-card --png 出图 ${pw}px（dsf 生效）" \
          || bad "render-card --png 出图宽 ${pw}"
      else bad "render-card 失败"; sed -n '1,8p' /tmp/av-rc1.log /tmp/av-rc2.log; fi
    else bad "找不到已填充的卡 HTML，render-card 没测到"; fi
  else bad "storyboard 渲染失败"; sed -n '1,12p' /tmp/av-sb1.log; fi
else
  printf '  ○ 跳过真实渲染（本机没有 playwright）\n'
fi
rm -rf "$SX/work" "$SX/html" "$SX/shots.tsv" "$SX/one.webm" "$SX/one.png"
fi

# ---------------------------------------------------------------- 3.38
if [ "$SKIP_RENDER" = 1 ]; then
  sec "零 context 冒烟（已跳过 --skip-render）"
else
sec "零 context 冒烟：从 init-project 起，无任何 API key 走到 audit"
ZC="$ROOT/tests/fixtures/zc"; rm -rf "$ZC"
if "$ROOT/lib/init-project.sh" "$ZC" >/tmp/av-zc0.log 2>&1; then
  grep -q '<repo>' /tmp/av-zc0.log && bad "init-project 打印了字面量 <repo>，读的人得自己猜路径" \
    || ok "init-project 建好骨架并打印真实 repo 路径"
else bad "init-project 失败"; sed -n '1,8p' /tmp/av-zc0.log; fi
# 故意写 5 句，比 init 模板的 shots.tsv 多 —— 缺行必须被自动补上
cat > "$ZC/clips.json" <<'JSONEOF'
[
 {"name":"c01","text":"他三天没回。你点开他的朋友圈，第十七次。"},
 {"name":"c02","text":"你没想好怎么开口，先偷偷查了你俩合不合。"},
 {"name":"c03","text":"别不好意思，这几乎是本能。"},
 {"name":"c04","text":"老祖宗合婚看的就是八字合盘。"},
 {"name":"c05","text":"就当是换个角度认识自己。auramate。"}
]
JSONEOF
if "$ROOT/lib/make-placeholders.sh" "$ZC" --footage >/tmp/av-zc1.log 2>&1; then
  grep -q '补了 2 行缺的拍' /tmp/av-zc1.log && ok "占位配音+素材已造，shots.tsv 缺的拍被自动补齐" \
    || { bad "shots.tsv 缺行没补上"; grep 'shots.tsv' /tmp/av-zc1.log; }
else bad "make-placeholders 失败"; sed -n '1,10p' /tmp/av-zc1.log; fi
if "$ROOT/lib/build-vertical.sh" --project "$ZC" --out "$ZC/draft-nosub.mp4" >/tmp/av-zc2.log 2>&1 \
   && /usr/bin/python3 "$ROOT/lib/gen-subs.py" --project "$ZC" >/tmp/av-zc3.log 2>&1 \
   && "$ROOT/lib/burn-subs.sh" "$ZC/draft-nosub.mp4" "$ZC/draft-v1.mp4" \
        --manifest "$ZC/subs/manifest.tsv" >/tmp/av-zc4.log 2>&1; then
  w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$ZC/draft-v1.mp4")
  h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$ZC/draft-v1.mp4")
  [ "$w" = 1080 ] && [ "$h" = 1920 ] && ok "无 key 也出片：${w}×${h}" || bad "出片 ${w}×${h}"
else bad "无 key 路径出片失败"; sed -n '1,10p' /tmp/av-zc2.log /tmp/av-zc4.log; fi
if "$ROOT/lib/audit-video.sh" --project "$ZC" --video "$ZC/draft-v1.mp4" --target 10-40 >/tmp/av-zc5.log 2>&1; then
  grep -q '占位配音' /tmp/av-zc5.log && ok "audit 点名了占位配音（不会静默当成能交付）" \
    || bad "audit 没识别出占位配音"
else bad "audit 在零 context 工程上失败"; sed -n '1,30p' /tmp/av-zc5.log; fi
rm -rf "$ZC"
fi

# ---------------------------------------------------------------- 3.39
if [ "$SKIP_RENDER" = 1 ] || ! node -e "require('playwright')" 2>/dev/null; then
  sec "README demo（已跳过：--skip-render 或无 playwright）"
else
sec "卡模板预览片可复现（README 里那段命令原样跑）"
DV="$ROOT/examples/demo-vertical"
rm -rf "$DV/audio" "$DV/html" "$DV/work" "$DV/subs" "$DV"/demo-*.mp4
if "$ROOT/lib/make-placeholders.sh" "$DV" >/tmp/av-dv0.log 2>&1 \
   && node "$ROOT/lib/storyboard.js" --project "$DV" >/tmp/av-dv1.log 2>&1 \
   && "$ROOT/lib/build-vertical.sh" --project "$DV" --out "$DV/demo-nosub.mp4" >/tmp/av-dv2.log 2>&1 \
   && /usr/bin/python3 "$ROOT/lib/gen-subs.py" --project "$DV" --skip c03 --no-merge >/tmp/av-dv3.log 2>&1 \
   && "$ROOT/lib/burn-subs.sh" "$DV/demo-nosub.mp4" "$DV/demo-v1.mp4" \
        --manifest "$DV/subs/manifest.tsv" >/tmp/av-dv4.log 2>&1; then
  w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$DV/demo-v1.mp4")
  h=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$DV/demo-v1.mp4")
  d=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$DV/demo-v1.mp4")
  [ "$w" = 1080 ] && [ "$h" = 1920 ] && ok "demo 复现成功：${w}×${h} / ${d}s" || bad "demo 出片 ${w}×${h}"
  # 渲出来的卡不许比这一拍短，否则那一拍会黑屏（真踩过）
  grep -q '还短' /tmp/av-dv1.log && bad "有卡比这一拍短 —— 加大 storyboard.js --margin" \
    || ok "5 张卡都不短于对应拍长"
  if "$ROOT/lib/audit-video.sh" --project "$DV" --video "$DV/demo-v1.mp4" --target 15-30 >/tmp/av-dv5.log 2>&1; then
    ok "模板预览片过审计（README 里引用的输出仍然成立）"
  else bad "demo 没过审计"; grep '✗' /tmp/av-dv5.log | sed 's/^/    /'; fi
else
  bad "README 上的 demo 命令跑不通了"
  for f in /tmp/av-dv0.log /tmp/av-dv1.log /tmp/av-dv2.log /tmp/av-dv4.log; do sed -n '1,5p' "$f" 2>/dev/null; done
fi
rm -rf "$DV/audio" "$DV/html" "$DV/work" "$DV/subs" "$DV"/demo-*.mp4
fi

# ---------------------------------------------------------------- 3.4
sec "脚本 linter"
# 真实发过的稿子必须放行（阈值不能严到把已交付内容判成错）
REAL=/Users/macmini003/ops-bilibili/projects/xuanxue-loop/clips.json
if [ -f "$REAL" ]; then
  if /usr/bin/python3 lib/check-script.py --clips "$REAL" --target 40-60 >/tmp/av-sreal.log 2>&1; then
    ok "真实交付稿放行（阈值没有过严）"
  else bad "真实交付稿被判硬错误 —— 阈值过严"; grep '✗' /tmp/av-sreal.log; fi
else
  printf '  ○ 跳过真实稿回归（本机没有 %s）\n' "$REAL"
fi
if /usr/bin/python3 lib/check-script.py --project tests/fixtures/script-bad --target 40-60 >/tmp/av-sbad.log 2>&1; then
  bad "坏稿没被拦住（应 exit 1）"
else
  grep -q 'ta' /tmp/av-sbad.log && grep -q '超过 15s' /tmp/av-sbad.log \
    && ok "坏稿被拦下（ta + 超长拍都命中）" || { bad "坏稿命中项不对"; grep '✗' /tmp/av-sbad.log; }
fi
if /usr/bin/python3 lib/check-script.py --project examples/hello-vertical --target 5-30 >/tmp/av-sex.log 2>&1; then
  ok "样例工程脚本通过"
else bad "样例工程脚本有硬错误"; grep '✗' /tmp/av-sex.log; fi

# ---------------------------------------------------------------- 3.45
sec "人味儿 linter"
HX="$ROOT/tests/fixtures/human"; rm -rf "$HX"; mkdir -p "$HX"
cat > "$HX/clips.json" <<'JEOF'
[{"name":"c01","text":"这不是一次简单的升级——而是一次彻底的重构。"},
 {"name":"c02","text":"它标志着我们赋能行业的匠心时刻。"},
 {"name":"c03","text":"让我们看看结果。未来可期。"}]
JEOF
/usr/bin/python3 lib/check-humanness.py --project "$HX" >/tmp/av-hu.log 2>&1 || true
nh=$(grep -c '^  ! ' /tmp/av-hu.log || true)
[ "$nh" -ge 4 ] && ok "AI 腔样本被挑出 $nh 处句式痕迹" || { bad "只挑出 $nh 处，词表可能坏了"; cat /tmp/av-hu.log; }
/usr/bin/python3 lib/check-humanness.py --project examples/hello-vertical >/tmp/av-hu2.log 2>&1 || true
grep -q '句式痕迹 0 处' /tmp/av-hu2.log && ok "样例工程无句式痕迹（无误报）" || { bad "样例被误报"; grep '^  ! ' /tmp/av-hu2.log; }
rm -rf "$HX"

# ---------------------------------------------------------------- 3.5
sec "合规 linter"
if /usr/bin/python3 lib/check-compliance.py --project tests/fixtures/compliance-bad >/tmp/av-cbad.log 2>&1; then
  bad "违规样本没被拦住（应 exit 1）"
else
  n=$(grep -c 'BLOCK \[' /tmp/av-cbad.log || true)
  [ "$n" -ge 6 ] && ok "违规样本被拦下，命中 $n 条 BLOCK" || bad "违规样本只命中 $n 条 BLOCK，词表可能被改坏"
fi
if /usr/bin/python3 lib/check-compliance.py --project tests/fixtures/compliance-good >/tmp/av-cgood.log 2>&1; then
  ok "合规样本放行（无误报）"
else
  bad "合规样本被误报"; sed -n '1,20p' /tmp/av-cgood.log
fi
if /usr/bin/python3 lib/check-compliance.py --project examples/hello-vertical >/tmp/av-cex.log 2>&1; then
  ok "样例工程 hello-vertical 合规通过"
else
  bad "样例工程自己就不合规"; sed -n '1,20p' /tmp/av-cex.log
fi

# ---------------------------------------------------------------- 4
if [ "$SKIP_RENDER" = 1 ]; then
  sec "端到端渲染（已跳过 --skip-render）"
else
sec "端到端渲染 examples/hello-vertical"
EX="$ROOT/examples/hello-vertical"
rm -rf "$EX/work" "$EX/subs" "$EX/audio" "$EX/footage" "$EX"/hello-*.mp4 2>/dev/null
if ! "$EX/make-fixtures.sh" >/tmp/av-fixtures.log 2>&1; then
  bad "make-fixtures.sh 失败"; sed -n '1,20p' /tmp/av-fixtures.log
else
  ok "假素材 + 假配音已生成"
  if "$ROOT/lib/verify-audio.sh" "$EX/audio" "$EX/clips.json" >/tmp/av-audio.log 2>&1; then
    ok "verify-audio 通过"
  else bad "verify-audio 失败"; sed -n '1,20p' /tmp/av-audio.log; fi

  if "$ROOT/lib/build-vertical.sh" --project "$EX" --out "$EX/hello-nosub.mp4" >/tmp/av-build.log 2>&1; then
    ok "build-vertical 出片"
  else bad "build-vertical 失败"; sed -n '1,30p' /tmp/av-build.log; fi

  # 相对 --out 必须按当前工作目录解（曾经按项目目录解，会拼成 a/b/a/b/out.mp4）
  ( cd "$ROOT" && "$ROOT/lib/build-vertical.sh" --project examples/hello-vertical \
      --out examples/hello-vertical/relout.mp4 >/tmp/av-relout.log 2>&1 )
  [ -f "$EX/relout.mp4" ] && { ok "相对 --out 按 cwd 解析（不会重复拼项目路径）"; rm -f "$EX/relout.mp4"; } \
    || { bad "相对 --out 解析错"; sed -n '1,6p' /tmp/av-relout.log; }

  if /usr/bin/python3 "$ROOT/lib/gen-subs.py" --project "$EX" >/tmp/av-subs.log 2>&1; then
    n=$(wc -l < "$EX/subs/manifest.tsv" | tr -d ' ')
    ok "gen-subs 生成 $n 行字幕"
  else bad "gen-subs 失败"; sed -n '1,20p' /tmp/av-subs.log; fi

  if "$ROOT/lib/burn-subs.sh" "$EX/hello-nosub.mp4" "$EX/hello-v1.mp4" --manifest "$EX/subs/manifest.tsv" >/tmp/av-burn.log 2>&1; then
    ok "burn-subs 烧字幕"
  else bad "burn-subs 失败"; sed -n '1,20p' /tmp/av-burn.log; fi

  # 节奏检测：拿造好的成片量一遍，判据本身要跑得通
  if /usr/bin/python3 "$ROOT/lib/check-rhythm.py" "$EX/hello-nosub.mp4" >/tmp/av-rhy.log 2>&1 \
     || grep -q 'RHYTHM' /tmp/av-rhy.log; then
    grep -q '节奏图' /tmp/av-rhy.log && ok "check-rhythm 出节奏图并给判据" \
      || bad "check-rhythm 没输出节奏图"
  else bad "check-rhythm 跑挂了"; sed -n '1,15p' /tmp/av-rhy.log; fi

  # 标注层：大字 PNG + 两层 manifest 一次压完（字幕在底、标注在中上）
  printf '[{"at":0.2,"dur":1.2,"text":"大字标注"},{"at":2.0,"dur":1.0,"text":"不是字幕\\n是标注"}]' > "$EX/callouts.json"
  if /usr/bin/python3 "$ROOT/lib/gen-callouts.py" --callouts "$EX/callouts.json" --out "$EX/callouts" \
       --w 1080 --h 1920 >/tmp/av-callout.log 2>&1; then
    n=$(wc -l < "$EX/callouts/manifest.tsv" | tr -d ' ')
    [ "$n" = 2 ] && ok "gen-callouts 生成 $n 条大字标注" || bad "标注条数不对: $n"
  else bad "gen-callouts 失败"; sed -n '1,20p' /tmp/av-callout.log; fi

  if "$ROOT/lib/burn-subs.sh" "$EX/hello-nosub.mp4" "$EX/hello-v2.mp4" \
       --manifest "$EX/subs/manifest.tsv" --manifest "$EX/callouts/manifest.tsv" >/tmp/av-burn2.log 2>&1; then
    grep -q '2 层' /tmp/av-burn2.log && ok "burn-subs 一次压两层（字幕 + 标注）" \
      || bad "--manifest 给两次却没按两层处理"
    a=$(ffprobe -v error -show_entries format=size -of csv=p=0 "$EX/hello-v1.mp4")
    b=$(ffprobe -v error -show_entries format=size -of csv=p=0 "$EX/hello-v2.mp4")
    [ "$a" != "$b" ] && ok "两层版和只有字幕版产物不同（标注确实烧上了）" \
      || bad "加了标注层但产物没变"
  else bad "burn-subs 两层失败"; sed -n '1,20p' /tmp/av-burn2.log; fi

  if [ -f "$EX/hello-v1.mp4" ]; then
    if "$ROOT/lib/verify-output.sh" "$EX/hello-v1.mp4" --expect-w 1080 --expect-h 1920 --fps 30 --min-dur 5 --max-dur 60 >/tmp/av-verify.log 2>&1; then
      ok "verify-output 全绿：$(grep -E '^  [0-9]+x' /tmp/av-verify.log | head -1 | sed 's/^ *//')"
    else bad "verify-output 失败"; cat /tmp/av-verify.log; fi
    # 字幕确实叠上去了：带字幕版应该比无字幕版画面有差异
    a=$(ffprobe -v error -show_entries format=size -of csv=p=0 "$EX/hello-nosub.mp4")
    b=$(ffprobe -v error -show_entries format=size -of csv=p=0 "$EX/hello-v1.mp4")
    [ "$a" != "$b" ] && ok "带字幕版与无字幕版产物不同（字幕确实烧上了）" || bad "带字幕版与无字幕版字节数相同，字幕可能没生效"

    # ---- 质量闸门 ----
    cp "$EX/hello-v1.mp4" "$EX/hello-demo-v1.mp4"
    if "$ROOT/lib/audit-video.sh" --project "$EX" --video "$EX/hello-demo-v1.mp4" \
         --target 5-30 >/tmp/av-audit.log 2>&1; then
      grep -q '^  画面构成:' /tmp/av-audit.log && ok "audit 通过，画面构成 $(grep -m1 '^  画面构成:' /tmp/av-audit.log | sed 's/^  画面构成: //')" \
        || bad "audit 没统计画面构成"
      grep -q '只有人能判的' /tmp/av-audit.log && ok "audit 输出了人工清单（没把它当成已通过）" || bad "audit 缺人工清单"
    else bad "audit 在样例工程上失败"; sed -n '1,40p' /tmp/av-audit.log; fi
    # 坏成片必须被拦：分辨率不对
    ffmpeg -nostdin -y -v error -f lavfi -i "testsrc2=size=640x360:rate=30:duration=6" \
      -f lavfi -i "sine=frequency=300:duration=6" -c:v libx264 -crf 28 -pix_fmt yuv420p \
      -c:a aac -shortest "$EX/bad-v1.mp4" 2>/dev/null
    if "$ROOT/lib/audit-video.sh" --project "$EX" --video "$EX/bad-v1.mp4" --target 5-30 >/tmp/av-audit2.log 2>&1; then
      bad "坏成片（640×360）没被 audit 拦住"
    else ok "坏成片被 audit 拦下"; fi
    rm -f "$EX/hello-demo-v1.mp4" "$EX/bad-v1.mp4"
  fi
fi
fi

# ----------------------------------------------------------------
printf '\n'
[ "$fail" = 0 ] && { echo "VALIDATE OK"; exit 0; } || { echo "VALIDATE FAILED"; exit 1; }
