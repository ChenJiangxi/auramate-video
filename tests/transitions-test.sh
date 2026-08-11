#!/usr/bin/env bash
# transitions-test.sh — 验转场没有偷偷动时间轴。被 tests/validate.sh 调用。
#
# 转场最容易出的事故不是「不好看」，是**悄悄改了音画关系**：
# 交叉溶解要两段素材重叠，重叠多少总长就短多少，于是每一句都比配音早／晚一点，
# 越到后面差得越多，最后一句直接被 -shortest 切掉。所以这里查的是：
#   ① 开不开转场，成片总时长一样
#   ② 开不开转场，**每句开口那一帧**画面一样（转场只发生在句末的停顿里）
#   ③ 转场中间那一帧确实在混合（真有转场，不是写了参数没生效）
#   ④ 第7列能逐拍指定；auto 遇到同一素材判硬切；转场超过上一拍自动降级
#   ⑤ 素材不够长时冻末帧，成片不短于音轨（配音一秒不丢）
#
# 输出 "✓ …" / "✗ …"，退出码 0/1。
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EX="$ROOT/examples/hello-vertical"
TMP="${TMPDIR:-/tmp}/av-trans.$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

bad=0
ok(){  printf '  ✓ %s\n' "$1"; }
no(){  printf '  ✗ %s\n' "$1"; bad=1; }
dur(){ ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }

[ -x "$EX/make-fixtures.sh" ] || { echo "  ✗ 缺 $EX/make-fixtures.sh"; exit 1; }
rm -rf "$EX/work" "$EX/audio" "$EX/footage"
"$EX/make-fixtures.sh" >"$TMP/fx.log" 2>&1 || { echo "  ✗ 造假素材失败"; sed -n '1,10p' "$TMP/fx.log"; exit 1; }

B="$ROOT/lib/build-vertical.sh"
"$B" --project "$EX" --out "$TMP/soft.mp4" >"$TMP/soft.log" 2>&1 || { no "转场版没出片"; sed -n '1,20p' "$TMP/soft.log"; exit 1; }
"$B" --project "$EX" --no-xfade --out "$TMP/hard.mp4" >"$TMP/hard.log" 2>&1 || { no "硬切版没出片"; exit 1; }

# ---------- ① 总时长 ----------
ds="$(dur "$TMP/soft.mp4")"; dh="$(dur "$TMP/hard.mp4")"; da="$(dur "$EX/work/voice.m4a")"
if awk -v a="$ds" -v b="$dh" 'BEGIN{ exit !((a-b<0.02)&&(b-a<0.02)) }'; then
  ok "开不开转场总时长一致（${ds}s）"
else no "转场把总时长改了：转场 ${ds}s vs 硬切 ${dh}s"; fi
if awk -v v="$ds" -v a="$da" 'BEGIN{ exit !(v>=a-0.005) }'; then
  ok "成片不短于音轨（${ds}s ≥ ${da}s，配音不会被切）"
else no "成片 ${ds}s 短于音轨 ${da}s —— 末尾配音会被 -shortest 吃掉"; fi

# ---------- ⓪ 音画不许逐拍漂移 ----------
# 每拍单独编码时 -t 会把时长向上取整到整帧，一拍多几毫秒，concat 起来逐拍累加。
# 真实的 8 拍片子量出来末拍画面晚 171ms —— 这条测试就是钉住它别回来。
DRIFT="$(/usr/bin/env python3 - "$EX" <<'PY'
import json, os, subprocess, sys
p = sys.argv[1]
def d(f):
    return float(subprocess.run(['ffprobe','-v','error','-show_entries','format=duration',
                                 '-of','csv=p=0', f], capture_output=True, text=True).stdout)
clips = json.load(open(os.path.join(p,'clips.json'), encoding='utf-8'))
ta = tv = worst = 0.0
for i, c in enumerate(clips):
    ta += d(os.path.join(p,'audio', c['name']+'.mp3')) + 0.25
    tv += d(os.path.join(p,'work', f'v{i+1:02d}.mp4'))
    worst = max(worst, abs(tv - ta))
print(f'{worst*1000:.0f}')
PY
)"
if awk -v v="${DRIFT:-999}" 'BEGIN{ exit !(v<=17) }'; then
  ok "音画零累积漂移（最大 ${DRIFT}ms，半帧以内）"
else no "音画逐拍漂移 ${DRIFT}ms —— 拍长没按绝对边界对齐到整帧"; fi

# ---------- 拍边界（拍长 = 配音 + GAP）----------
BOUND="$(/usr/bin/env python3 - "$EX" <<'PY'
import json, os, subprocess, sys
p = sys.argv[1]
clips = json.load(open(os.path.join(p, 'clips.json'), encoding='utf-8'))
t = 0.0; out = []
for c in clips[:-1]:
    d = float(subprocess.run(['ffprobe','-v','error','-show_entries','format=duration',
         '-of','csv=p=0', os.path.join(p,'audio', c['name']+'.mp3')],
         capture_output=True, text=True).stdout.strip())
    t += d + 0.25
    out.append(f'{t:.3f}')
print(' '.join(out))
PY
)"
[ -n "$BOUND" ] || { no "算不出拍边界"; exit 1; }

# ---------- ②③ 逐个边界比帧 ----------
CMP="$ROOT/tests/cmp-frame.py"
same_all=1; diff_all=1
for t in $BOUND; do
  after="$(awk -v x="$t" 'BEGIN{printf "%.3f", x+0.06}')"   # 刚开口
  mid="$(awk   -v x="$t" 'BEGIN{printf "%.3f", x-0.11}')"   # 转场中间
  d1="$(/usr/bin/env python3 "$CMP" "$TMP/soft.mp4" "$TMP/hard.mp4" "$after")"
  d2="$(/usr/bin/env python3 "$CMP" "$TMP/soft.mp4" "$TMP/hard.mp4" "$mid")"
  awk -v v="$d1" 'BEGIN{ exit !(v<3.0) }' || { same_all=0; echo "     边界 ${t}s：开口那一帧差 $d1"; }
  awk -v v="$d2" 'BEGIN{ exit !(v>8.0) }' || { diff_all=0; echo "     边界 ${t}s：转场中间差 ${d2}（太小，转场可能没生效）"; }
done
[ "$same_all" = 1 ] && ok "每句开口那一帧和硬切版一致（转场只吃句末的停顿）" \
                    || no "开口那一帧被转场改了 —— 观众在关键时刻看到的东西变了"
[ "$diff_all" = 1 ] && ok "转场中间那一帧确实在混合（不是写了参数没生效）" \
                    || no "转场中间和硬切一样，转场没真的发生"

# ---------- ④ 逐拍指定 / auto / 降级 ----------
/usr/bin/env python3 - "$EX" "$TMP" <<'PY'
import sys, os
ex, tmp = sys.argv[1], sys.argv[2]
rows = [l.rstrip('\n').split('\t') for l in open(os.path.join(ex,'shots.tsv'), encoding='utf-8') if l.strip()]
for r in rows:
    while len(r) < 6: r.append('')
    del r[7:]
a = [r[:6] for r in rows]; a[1] = a[1] + ['slideup:0.30']; a[2] = a[2] + ['cut']
open(os.path.join(tmp,'col7.tsv'),'w',encoding='utf-8').write('\n'.join('\t'.join(r) for r in a)+'\n')
b = [r[:6] for r in rows]; b[1][1] = b[0][1]; b[1][2] = b[0][2]      # 让 c02 和 c01 同素材
open(os.path.join(tmp,'same.tsv'),'w',encoding='utf-8').write('\n'.join('\t'.join(r) for r in b)+'\n')
PY

"$B" --project "$EX" --shots "$TMP/col7.tsv" --out "$TMP/c7.mp4" >"$TMP/c7.log" 2>&1
grep -q 'slideup 0.3' "$TMP/c7.log" && grep -q '← 硬切' "$TMP/c7.log" \
  && ok "shots.tsv 第7列能逐拍指定转场（含 cut）" || { no "第7列没生效"; grep '←' "$TMP/c7.log"; }
awk -v a="$(dur "$TMP/c7.mp4")" -v b="$ds" 'BEGIN{ exit !((a-b<0.02)&&(b-a<0.02)) }' \
  && ok "换了转场类型和时长，总时长还是不变" || no "指定转场后总时长变了"

"$B" --project "$EX" --shots "$TMP/same.tsv" --out "$TMP/sm.mp4" >"$TMP/sm.log" 2>&1
grep -q 'c02  ← 硬切' "$TMP/sm.log" \
  && ok "auto 遇到前后同一素材判硬切（同源叠化只会糊成一团）" \
  || { no "auto 没识别同源"; grep '←' "$TMP/sm.log"; }

"$B" --project "$EX" --xfade 9 --out "$TMP/big.mp4" >"$TMP/big.log" 2>&1
grep -q '不短于上一拍' "$TMP/big.log" && grep -q '超过 GAP' "$TMP/big.log" \
  && ok "转场长过上一拍会警告并降级成硬切" || { no "超长转场没被拦"; grep '⚠' "$TMP/big.log"; }

# ---------- ⑤ 素材不够长 ----------
ffmpeg -nostdin -y -v error -f lavfi -i "color=c=orange:s=720x1280:r=30:d=1.2" \
  -c:v libx264 -crf 20 -pix_fmt yuv420p "$TMP/short.mp4"
/usr/bin/env python3 - "$EX" "$TMP" <<'PY'
import sys, os
ex, tmp = sys.argv[1], sys.argv[2]
rows = [l.rstrip('\n').split('\t') for l in open(os.path.join(ex,'shots.tsv'), encoding='utf-8') if l.strip()]
for r in rows:
    while len(r) < 6: r.append('')
    del r[6:]
rows[-1][1] = 'full'; rows[-1][2] = os.path.join(tmp,'short.mp4'); rows[-1][3] = '0'
open(os.path.join(tmp,'short.tsv'),'w',encoding='utf-8').write('\n'.join('\t'.join(r) for r in rows)+'\n')
PY
"$B" --project "$EX" --shots "$TMP/short.tsv" --out "$TMP/sh.mp4" >"$TMP/sh.log" 2>&1
grep -q '冻结末帧补' "$TMP/sh.log" && ok "素材不够长会冻末帧并喊出来（不再静默丢画面）" \
  || { no "素材不够长没被处理"; grep '⚠' "$TMP/sh.log"; }
dsh="$(dur "$TMP/sh.mp4")"
awk -v v="$dsh" -v a="$da" 'BEGIN{ exit !(v>=a-0.005) }' \
  && ok "素材不够长时配音仍然一秒不丢（${dsh}s ≥ ${da}s）" \
  || no "素材不够长导致配音被切：成片 ${dsh}s < 音轨 ${da}s"

exit $bad
