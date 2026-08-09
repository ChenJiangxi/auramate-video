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
rm -rf "$SX/work" "$SX/html" "$SX/shots.tsv"
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
  else bad "storyboard 渲染失败"; sed -n '1,12p' /tmp/av-sb1.log; fi
else
  printf '  ○ 跳过真实渲染（本机没有 playwright）\n'
fi
rm -rf "$SX/work" "$SX/html" "$SX/shots.tsv"
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
