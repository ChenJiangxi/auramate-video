#!/usr/bin/env bash
# motion.sh — 给录屏/素材加镜头运动。产品演示片靠推拉把注意力带到该看的地方，
# 光是「静态裁一块」既呆板、字也读不清。
#
# 用法:
#   motion.sh <src> <out> --dur <秒> [--ss <起始秒>] --move <运动> [选项]
#
# 运动（--move）:
#   punch-in    从全屏缓推到目标框（最常用：先看全貌，再把重点顶到脸上）
#               ⚠ 终点框要取源宽的 55–70%，也就是起终缩放 ≥1.4×。
#                 取 90% 那种「推」观众只会看成画面在飘。
#   pull-out    反过来，从目标框拉回全屏（用于"原来在这儿"的揭示）
#   pan         在两个框之间平移/缩放（跟着长页面往下读）
#   kenburns    极缓慢的缩放漂移，给静止画面一点呼吸
#   hold        不动（等价于 zoom-crop，放这里是为了 shots 里口径统一）
#
# 目标框:
#   --to   W:H:X:Y     终点框（punch-in / pan 必须）
#   --from W:H:X:Y     起点框（pull-out / pan 必须；不给就是全屏）
#   --zoom 1.35        没有精确框时，按倍数居中推（--cx/--cy 移中心，0–1）
#
# 其它:
#   --ease inout|linear   默认 inout（两头慢中间快，像真人推镜）
#   --out-w 1080 --out-h 1920 --fps 30 --crf 19
#   --grid                只导一张带坐标网格的样帧，用来量框（agent 看不见画面就靠它）
#
# 怎么量框：先 --grid 导样帧，数格子得到 W:H:X:Y。
# 终点框的宽高比**不用**等于输出比例，脚本会按输出比例把它补齐再推。
# ⚠ 喂给 `read` 的 awk，printf 末尾**必须**有 \n —— 少了 read 返回 1，
#   set -e 会把脚本静默干掉（什么都不打印，极难查）。fit-vertical.sh 踩过一次，这里又踩一次。
set -euo pipefail
FF=${FF:-ffmpeg}; FP=${FP:-ffprobe}

SRC="${1:-}"; OUT="${2:-}"; shift 2 2>/dev/null || true
[ -n "$SRC" ] && [ -f "$SRC" ] && [ -n "$OUT" ] || { sed -n '2,30p' "$0"; exit 2; }

DUR=""; SS=0; MOVE=punch-in; TO=""; FROM=""; ZOOM=""; CX=0.5; CY=0.5
EASE=inout; OW=1080; OH=1920; FPS=30; CRF=19; GRID=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dur) DUR="$2"; shift 2;;
    --ss) SS="$2"; shift 2;;
    --move) MOVE="$2"; shift 2;;
    --to) TO="$2"; shift 2;;
    --from) FROM="$2"; shift 2;;
    --zoom) ZOOM="$2"; shift 2;;
    --cx) CX="$2"; shift 2;;
    --cy) CY="$2"; shift 2;;
    --ease) EASE="$2"; shift 2;;
    --out-w) OW="$2"; shift 2;;
    --out-h) OH="$2"; shift 2;;
    --fps) FPS="$2"; shift 2;;
    --crf) CRF="$2"; shift 2;;
    --grid) GRID=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

IFS=',' read -r SW SH < <("$FP" -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$SRC")
SDUR=$("$FP" -v error -show_entries format=duration -of csv=p=0 "$SRC")

if [ "$GRID" = 1 ]; then
  G="${OUT%.*}.grid.png"; mkdir -p "$(dirname "$G")"
  gx=$((SW / 10)); gy=$((SH / 10))
  "$FF" -nostdin -y -v error -ss "$SS" -i "$SRC" -frames:v 1 \
    -vf "drawgrid=width=${gx}:height=${gy}:thickness=2:color=cyan@0.7" "$G"
  echo "网格样帧 → $G  （源 ${SW}x${SH}，每格 ${gx}x${gy}）"
  echo "数格子得到 W:H:X:Y，填进 --to / --from"
  exit 0
fi
[ -n "$DUR" ] || { echo "需要 --dur <秒>" >&2; exit 2; }

avail=$(awk -v d="$SDUR" -v s="$SS" 'BEGIN{printf "%.2f", d-s}')
awk -v a="$avail" -v d="$DUR" 'BEGIN{exit !(a >= d-0.05)}' \
  || { echo "✗ 素材不够长：从 ${SS}s 起只剩 ${avail}s，这一拍要 ${DUR}s" >&2; exit 4; }

# ---- 把「框」规整成输出宽高比，并夹进画面内 ----
# 终点框可以随手量，宽高比不对没关系 —— 按输出比例扩到能包住它，再夹边界。
norm_box(){   # $1=W:H:X:Y  → 回 "w h x y"
  awk -v box="$1" -v sw="$SW" -v sh="$SH" -v ow="$OW" -v oh="$OH" 'BEGIN{
    n=split(box,b,":"); w=b[1]; h=b[2]; x=b[3]; y=b[4];
    ar=ow/oh;
    if (w/h > ar) h = w/ar; else w = h*ar;         # 按输出比例扩
    if (w > sw) { w=sw; h=w/ar }
    if (h > sh) { h=sh; w=h*ar }
    cx=b[3]+b[1]/2; cy=b[4]+b[2]/2;                 # 保持原中心
    x=cx-w/2; y=cy-h/2;
    if (x<0) x=0; if (y<0) y=0;
    if (x+w>sw) x=sw-w; if (y+h>sh) y=sh-h;
    printf "%d %d %d %d\n", int(w/2)*2, int(h/2)*2, int(x/2)*2, int(y/2)*2 }'
}
full_box(){
  awk -v sw="$SW" -v sh="$SH" -v ow="$OW" -v oh="$OH" 'BEGIN{
    ar=ow/oh; w=sw; h=w/ar; if (h>sh) { h=sh; w=h*ar }
    printf "%d %d %d %d\n", int(w/2)*2, int(h/2)*2, int((sw-w)/2/2)*2, int((sh-h)/2/2)*2 }'
}
zoom_box(){   # 按倍数居中（--cx/--cy 移中心）
  awk -v sw="$SW" -v sh="$SH" -v ow="$OW" -v oh="$OH" -v z="$1" -v cx="$CX" -v cy="$CY" 'BEGIN{
    ar=ow/oh; w=sw/z; h=w/ar; if (h>sh/z) { h=sh/z; w=h*ar }
    x=sw*cx-w/2; y=sh*cy-h/2;
    if (x<0) x=0; if (y<0) y=0;
    if (x+w>sw) x=sw-w; if (y+h>sh) y=sh-h;
    printf "%d %d %d %d\n", int(w/2)*2, int(h/2)*2, int(x/2)*2, int(y/2)*2 }'
}

case "$MOVE" in
  punch-in)
    read -r AW AH AX AY < <(full_box)
    if [ -n "$TO" ]; then read -r BW BH BX BY < <(norm_box "$TO")
    else read -r BW BH BX BY < <(zoom_box "${ZOOM:-1.35}"); fi;;
  pull-out)
    if [ -n "$FROM" ]; then read -r AW AH AX AY < <(norm_box "$FROM")
    else read -r AW AH AX AY < <(zoom_box "${ZOOM:-1.35}"); fi
    read -r BW BH BX BY < <(full_box);;
  pan)
    [ -n "$TO" ] || { echo "pan 需要 --to（--from 不给就是全屏）" >&2; exit 2; }
    if [ -n "$FROM" ]; then read -r AW AH AX AY < <(norm_box "$FROM")
    else read -r AW AH AX AY < <(full_box); fi
    read -r BW BH BX BY < <(norm_box "$TO");;
  kenburns)
    read -r AW AH AX AY < <(full_box)
    read -r BW BH BX BY < <(zoom_box "${ZOOM:-1.08}");;
  hold)
    if [ -n "$TO" ]; then read -r AW AH AX AY < <(norm_box "$TO")
    elif [ -n "$ZOOM" ]; then read -r AW AH AX AY < <(zoom_box "$ZOOM")
    else read -r AW AH AX AY < <(full_box); fi
    BW=$AW; BH=$AH; BX=$AX; BY=$AY;;
  *) echo "未知 --move: $MOVE" >&2; exit 2;;
esac

# 进度量 p：inout = smoothstep（两头慢中间快，像真人推镜）；linear = 匀速
if [ "$EASE" = linear ]; then
  P="min(t/${DUR}\,1)"
else
  P="(min(t/${DUR}\,1)*min(t/${DUR}\,1)*(3-2*min(t/${DUR}\,1)))"
fi

# crop 用时间表达式在两个框之间插值。除以 2 再乘 2 保证偶数，否则 libx264 报错。
CW="floor((${AW}+(${BW}-${AW})*${P})/2)*2"
CH="floor((${AH}+(${BH}-${AH})*${P})/2)*2"
CXE="floor((${AX}+(${BX}-${AX})*${P})/2)*2"
CYE="floor((${AY}+(${BY}-${AY})*${P})/2)*2"

# 终点框越小放大越多 —— 先把清晰度账算给人看
UPA=$(awk -v w="$AW" -v o="$OW" 'BEGIN{printf "%.2f", o/w}')
UPB=$(awk -v w="$BW" -v o="$OW" 'BEGIN{printf "%.2f", o/w}')
SHARP=""
awk -v a="$UPA" -v b="$UPB" 'BEGIN{exit !(a>1.0 || b>1.0)}' && SHARP=",unsharp=5:5:0.6"

echo "源 ${SW}x${SH} → ${MOVE}（${EASE}）"
echo "  起 ${AW}x${AH}@${AX},${AY} 放大 ${UPA}×  →  终 ${BW}x${BH}@${BX},${BY} 放大 ${UPB}×"
awk -v u="$UPB" 'BEGIN{exit !(u>2.0)}' && echo "  ⚠ 终点放大 ${UPB}× —— 会糊，别推这么近或提高录制分辨率" >&2
# 起点到终点的**相对**缩放才是观众看到的「推镜感」。差得太少就只是画面在飘，
# 看着像左右平移而不是推近 —— 这个坑我自己踩过：全片 1.06–1.12×，被一眼看穿。
ZR=$(awk -v a="$AW" -v b="$BW" 'BEGIN{printf "%.2f", (b>0)? a/b : 1}')
if [ "$MOVE" != hold ]; then
  awk -v z="$ZR" 'BEGIN{exit !(z<1.25 && z>0.8)}' && {
    echo "  ⚠ 起→终只缩放 ${ZR}× —— 这不叫推镜，观众看着就是平移。" >&2
    echo "     要有推近感，起终宽度比至少 1.4×（终点框取源宽的 55–70%）。" >&2
    echo "     推不动是因为源分辨率不够 → 提高录制分辨率，别把框放大凑合。" >&2
  }
fi
echo "  起→终缩放 ${ZR}×"

mkdir -p "$(dirname "$OUT")"
"$FF" -nostdin -y -v error -ss "$SS" -t "$DUR" -i "$SRC" -vf \
  "fps=${FPS},crop=w='${CW}':h='${CH}':x='${CXE}':y='${CYE}',scale=${OW}:${OH}:flags=lanczos${SHARP},setsar=1,format=yuv420p" \
  -an -c:v libx264 -crf "$CRF" -pix_fmt yuv420p "$OUT"

GW=$("$FP" -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$OUT")
GH=$("$FP" -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$OUT")
GD=$("$FP" -v error -show_entries format=duration -of csv=p=0 "$OUT")
[ "$GW" = "$OW" ] && [ "$GH" = "$OH" ] || { echo "✗ 输出 ${GW}x${GH} ≠ ${OW}x${OH}" >&2; exit 5; }
printf '  ✓ %s  %sx%s  %.2fs\n' "$OUT" "$GW" "$GH" "$GD"
