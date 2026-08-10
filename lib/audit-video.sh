#!/usr/bin/env bash
# audit-video.sh — 交付前一条命令跑完所有机械检查，出一份报告。
#
# 用法:
#   audit-video.sh --project <dir> [--video <成片.mp4>]
#        [--target 40-60] [--rate 6.35] [--w 1080] [--h 1920] [--fps 30]
#        [--gap 0.25] [--strict]
#
# 检查什么（机器能判的全在这）:
#   ① 脚本      check-script.py     句长 / 单拍时长 / ta / 钩子具体性
#   ② 合规      check-compliance.py 封建迷信红线，有 BLOCK 直接失败
#   ③ 配音      verify-audio.sh     每句非空 / 时长合理 / 不是静音
#   ④ 分镜      shots.tsv 覆盖每一拍，素材存在且够长
#   ⑤ 画面构成  按素材来源统计 卡片 / 真实切片 / 产品录屏 各占多少时长
#   ⑤b 清晰度    每拍源分辨率 → 放大倍数（>2× 判失败，>1.3× 提示）
#   ⑥ 字幕      条数 == 拆句数，没有漏行
#   ⑦ 成片      画幅 / 帧率 / 音轨 / faststart / 时长区间 / **静音段 + 末尾有没有声**
#   ⑧ 交付      文件名唯一带版本；交付包四件套是否齐
#
# 判不了的（只有人能判）会单独列成一张清单，别把它们当成「已通过」。
#
# 退出码: 0 全过 / 1 有硬失败 / 2 用法错
set -uo pipefail
FP=${FP:-ffprobe}
HERE="$(cd "$(dirname "$0")" && pwd)"
PY=/usr/bin/python3
[ -x "$PY" ] || PY=python3

PROJECT=""; VIDEO=""; TARGET="40-60"; RATE=6.35; W=1080; H=1920; FPS=30; GAP=0.25; STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --video) VIDEO="$2"; shift 2;;
    --target) TARGET="$2"; shift 2;;
    --rate) RATE="$2"; shift 2;;
    --w) W="$2"; shift 2;;
    --h) H="$2"; shift 2;;
    --fps) FPS="$2"; shift 2;;
    --gap) GAP="$2"; shift 2;;
    --strict) STRICT=1; shift;;
    -h|--help) sed -n '2,22p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$PROJECT" ] && [ -d "$PROJECT" ] || { echo "需要 --project <dir>" >&2; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd)"

hard=0; soft=0
sec(){ printf '\n\033[1m── %s\033[0m\n' "$1"; }
ok(){  printf '  ✓ %s\n' "$1"; }
bad(){ printf '  ✗ %s\n' "$1"; hard=1; }
warn(){ printf '  ! %s\n' "$1"; soft=$((soft+1)); }
skip(){ printf '  ○ %s\n' "$1"; }

echo "audit: $PROJECT"

# ---------------------------------------------------------------- ① 脚本
sec "① 脚本"
if [ -f "$PROJECT/clips.json" ]; then
  if "$PY" "$HERE/check-script.py" --project "$PROJECT" --rate "$RATE" --target "$TARGET" >/tmp/av-au-s.log 2>&1; then
    ok "$(grep -m1 '句 ·' /tmp/av-au-s.log | sed 's/^ *//')"
    n=$(grep -c '^  ! ' /tmp/av-au-s.log || true)
    [ "$n" -gt 0 ] && warn "脚本有 $n 条提示（自己看 check-script 输出判断）"
  else
    bad "脚本有硬错误"; grep '✗' /tmp/av-au-s.log | sed 's/^/    /'
  fi
else bad "缺 clips.json"; fi

# ---------------------------------------------------------------- ② 合规
sec "② 合规"
if "$PY" "$HERE/check-compliance.py" --project "$PROJECT" >/tmp/av-au-c.log 2>&1; then
  ok "$(grep -m1 'BLOCK ' /tmp/av-au-c.log | sed 's/^ *//')"
  grep -q '框定话术 无' /tmp/av-au-c.log && warn "全片没有框定话术"
  n=$(grep -c '^  ! WARN' /tmp/av-au-c.log || true)
  [ "$n" -gt 0 ] && warn "有 ${n} 条 WARN 需人工确认"
else
  bad "合规有 BLOCK —— 必须改完才能发"; grep 'BLOCK \[' /tmp/av-au-c.log | sed 's/^/    /'
fi

# ---------------------------------------------------------------- ③ 配音
sec "③ 配音"
if [ -d "$PROJECT/audio" ] && [ -f "$PROJECT/clips.json" ]; then
  if "$HERE/verify-audio.sh" "$PROJECT/audio" "$PROJECT/clips.json" >/tmp/av-au-a.log 2>&1; then
    ok "$(grep -m1 '配音总时长' /tmp/av-au-a.log | sed 's/^ *//')"
  else bad "配音有问题"; grep '✗' /tmp/av-au-a.log | sed 's/^/    /'; fi
  # 占位配音只看时长和响度是查不出来的，会一路静默通过 —— 必须单独点名
  [ -f "$PROJECT/audio/.placeholder" ] && \
    warn "audio/ 里是**占位配音**（见 audio/.placeholder）—— 绝不能交付，换成真配音后删掉该标记"
else skip "还没配音（audio/ 为空）"; fi

# ---------------------------------------------------------------- ④⑤ 分镜 + 画面构成
sec "④ 分镜覆盖 / ⑤ 画面构成"
if [ -f "$PROJECT/shots.tsv" ] && [ -f "$PROJECT/clips.json" ]; then
  "$PY" - "$PROJECT" "$GAP" <<'PYEOF' >/tmp/av-au-sh.log 2>&1
import json, os, subprocess, sys
P, GAP = sys.argv[1], float(sys.argv[2])
clips = json.load(open(os.path.join(P, 'clips.json'), encoding='utf-8'))
shots = {}
for line in open(os.path.join(P, 'shots.tsv'), encoding='utf-8'):
    f = line.rstrip('\n').split('\t')
    if len(f) >= 3 and f[0]:
        shots[f[0]] = (f[1], f[2], float(f[3]) if len(f) > 3 and f[3] else 0.0)

def dur(p):
    try:
        return float(subprocess.check_output(
            ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
             '-of', 'csv=p=0', p]).decode().strip())
    except Exception:
        return None

# 素材来源约定：html/ = 卡片，footage/ext = 真实切片，footage/rec 或 recordings = 产品录屏
def bucket(path, kind):
    p = path.replace('\\', '/')
    if kind == 'card' or '/beats/' in p or p.startswith('html/'): return '卡片'
    if '/ext/' in p: return '真实切片'
    if '/rec/' in p or 'recording' in p: return '产品录屏'
    return '其它'

errs, warns, totals, total = [], [], {}, 0.0
for c in clips:
    name = c['name']
    a = os.path.join(P, 'audio', f'{name}.mp3')
    beat = (dur(a) or 0) + GAP if os.path.exists(a) else None
    if name not in shots:
        errs.append(f'{name}: shots.tsv 里没有这一拍'); continue
    kind, src, ss = shots[name]
    sp = src if os.path.isabs(src) else os.path.join(P, src)
    if not os.path.exists(sp):
        errs.append(f'{name}: 素材不存在 {src}'); continue
    if beat is not None:
        sd = dur(sp)
        if sd is not None and sd - ss < beat - 0.05:
            errs.append(f'{name}: 素材从 {ss}s 起只剩 {sd-ss:.2f}s，这一拍要 {beat:.2f}s')
        b = bucket(src, kind)
        totals[b] = totals.get(b, 0.0) + beat
        total += beat
extra = [c for c in shots if c not in {x['name'] for x in clips}]
if extra: warns.append('shots.tsv 有多余的行: ' + ', '.join(extra))

for e in errs: print('ERR ' + e)
for w in warns: print('WARN ' + w)
if total > 0:
    parts = ' / '.join(f'{k} {v/total*100:.0f}%' for k, v in
                       sorted(totals.items(), key=lambda x: -x[1]))
    print(f'MIX {total:.1f}s  {parts}')
    card = totals.get('卡片', 0) / total
    prod = totals.get('产品录屏', 0) / total
    if card > 0.6: print(f'WARN 卡片占 {card*100:.0f}% —— 「整片都是卡」被明确否过，换真实素材')
    if prod and prod < 0.5: print(f'WARN 产品录屏占 {prod*100:.0f}% —— 产品片要求 ≥50%')
sys.exit(1 if errs else 0)
PYEOF
  rc=$?
  grep '^MIX ' /tmp/av-au-sh.log | sed 's/^MIX /  画面构成: /'
  while IFS= read -r l; do bad "${l#ERR }"; done < <(grep '^ERR ' /tmp/av-au-sh.log)
  while IFS= read -r l; do warn "${l#WARN }"; done < <(grep '^WARN ' /tmp/av-au-sh.log)
  [ "$rc" = 0 ] && ok "每一拍都有素材，且素材够长"
else skip "还没有 shots.tsv"; fi

# ---------------------------------------------------------------- ⑤b 清晰度
sec "⑤b 清晰度（源分辨率 → 放大倍数）"
if [ -f "$PROJECT/shots.tsv" ]; then
  blur=0
  while IFS=$'\t' read -r clip kind src ss extra; do
    [ -n "$clip" ] || continue
    case "$src" in /*) sp="$src";; *) sp="$PROJECT/$src";; esac
    [ -f "$sp" ] || continue
    sw="$("$FP" -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$sp" 2>/dev/null | head -1)"
    [ -n "$sw" ] || continue
    up="$(awk -v s="$sw" -v w="$W" 'BEGIN{printf "%.2f", w/s}')"
    if awk -v u="$up" 'BEGIN{exit !(u>2.0)}'; then
      bad "${clip}: 源宽 ${sw}px → 放大 ${up}× —— 太糊，换高分辨率源或重录"; blur=1
    elif awk -v u="$up" 'BEGIN{exit !(u>1.3)}'; then
      warn "${clip}: 源宽 ${sw}px → 放大 ${up}× —— 偏糊，能换源就换"
    fi
  done < "$PROJECT/shots.tsv"
  [ "$blur" = 0 ] && ok "没有超过 2× 的升采样"
  echo "  录制分辨率倒推：要在 ${W} 宽上做 1.5× 特写，源至少要 $(( W * 3 / 2 )) 宽"
else skip "还没有 shots.tsv"; fi

# ---------------------------------------------------------------- ⑥ 字幕
sec "⑥ 字幕"
MAN="$PROJECT/subs/manifest.tsv"
if [ -f "$MAN" ]; then
  got=$(grep -c . "$MAN")
  exp=$("$PY" - "$PROJECT" <<'PYEOF'
import json, os, re, sys
P = sys.argv[1]
clips = json.load(open(os.path.join(P, 'clips.json'), encoding='utf-8'))
n = 0
for c in clips:
    t = c['text'].replace('——', '，').replace('—', '，')
    parts = [p.strip() for p in re.split(r'[，。！？、；：]', t) if p.strip()]
    merged = []
    for p in parts:
        if merged and len(merged[-1]) + len(p) <= 15: merged[-1] += p
        else: merged.append(p)
    n += len(merged) or 1
print(n)
PYEOF
)
  if [ "$got" = "$exp" ]; then ok "字幕 ${got} 条 == 拆句数 ${exp}（没有漏行）"
  else warn "字幕 ${got} 条 ≠ 默认拆句数 ${exp} —— 用了 --skip 或 --no-merge 就正常，否则查漏行"; fi
else skip "还没生成字幕"; fi

# ---------------------------------------------------------------- ⑦ 成片
sec "⑦ 成片"
if [ -n "$VIDEO" ] && [ -f "$VIDEO" ]; then
  tmin="${TARGET%-*}"; tmax="${TARGET#*-}"
  if "$HERE/verify-output.sh" "$VIDEO" --expect-w "$W" --expect-h "$H" --fps "$FPS" \
        --min-dur "$tmin" --max-dur "$tmax" >/tmp/av-au-v.log 2>&1; then
    ok "$(sed -n '2p' /tmp/av-au-v.log | sed 's/^ *//')"
  else bad "成片不合格"; grep '✗' /tmp/av-au-v.log | sed 's/^/    /'; fi
  # 「后半段没声音」这类问题肉眼看不出来（画面照常走），必须机器查
  nsil=$(ffmpeg -hide_banner -nostats -i "$VIDEO" -af silencedetect=noise=-45dB:d=1.5 -f null - 2>&1 \
         | grep -c silence_start || true)
  if [ "${nsil:-0}" -gt 0 ]; then
    bad "有 ${nsil} 段 ≥1.5s 的静音 —— 检查是不是某几拍配音缺失或 -shortest 把音轨截了"
    ffmpeg -hide_banner -nostats -i "$VIDEO" -af silencedetect=noise=-45dB:d=1.5 -f null - 2>&1 \
      | grep silence_start | head -5 | sed 's/^/    /'
  else ok "全程无长静音段"; fi
  tailv=$(ffmpeg -hide_banner -nostats -sseof -5 -i "$VIDEO" -af volumedetect -f null - 2>&1 \
          | awk -F': ' '/mean_volume/{print $2}' | awk '{print $1}')
  if [ -n "$tailv" ]; then
    awk -v v="$tailv" 'BEGIN{exit !(v < -45)}' \
      && bad "末 5 秒基本无声（${tailv}dB）—— 收尾那句配音没进片子" \
      || ok "末 5 秒有声（${tailv}dB）"
  fi
else skip "没给 --video，跳过成片检查"; fi

# ---------------------------------------------------------------- ⑧ 交付
sec "⑧ 交付"
if [ -n "$VIDEO" ] && [ -f "$VIDEO" ]; then
  base="$(basename "$VIDEO")"; name="${base%.*}"
  case "$name" in
    *final*|*output*|*video*|*test*) warn "文件名 '$base' 太通用 —— 同名文件会被前端缓存，对方永远看到第一版";;
  esac
  echo "$name" | grep -qE 'v[0-9]+' && ok "文件名带版本号：$base" || warn "文件名里没有版本号（建议 -v3）"
  d="$(dirname "$VIDEO")"
  for f in cover.png caption.txt; do
    [ -f "$d/$f" ] || warn "同目录没有 ${f}（交付包四件套：视频 + 封面 + 文案 + 故事板）"
  done
else skip "没给 --video"; fi

# ---------------------------------------------------------------- 人工清单
sec "只有人能判的（机器一条都查不了）"
cat <<'EOF'
  [ ] 配音够不够有情绪 —— agent 听不到成品音
  [ ] 灵体/主视觉用的是不是「唤醒态」，不是休眠态
  [ ] 每句台词的画面「说什么显什么」，没有说 A 显 B
  [ ] 素材主题精准匹配（讲现代财运别用古钱币）
  [ ] 数字全是真跑出来的，没有编的
  [ ] 音色配题材（严肃用男主播，别用营销号女声）
  [ ] 封面是爆款风不是学术风
  [ ] 这条能不能火 —— 创意判断，只能人拍板
EOF

# ----------------------------------------------------------------
printf '\n'
if [ "$hard" = 0 ] && { [ "$soft" = 0 ] || [ "$STRICT" = 0 ]; }; then
  echo "AUDIT PASS（机器项全过，提示 ${soft} 条）"
  echo "→ 机器项过了不等于能发。上面那张人工清单必须真的过一遍。"
  exit 0
else
  [ "$hard" = 1 ] && echo "AUDIT FAIL —— 有硬失败，改完再跑" || echo "AUDIT FAIL（--strict：${soft} 条提示也算失败）"
  exit 1
fi
