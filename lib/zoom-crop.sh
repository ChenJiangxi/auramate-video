#!/usr/bin/env bash
# zoom-crop.sh — 产品录屏裁切放大。裸录屏直接用会被评为「录全屏感觉好小」。
#
# 用法:
#   zoom-crop.sh <src> <out> --dur <秒> [--ss <起始秒>]
#        [--auto | --zoom 1.5 [--cx 0.5] [--cy 0.5] | --crop W:H:X:Y]
#        [--out-w 1080] [--out-h 1920] [--fps 30] [--crf 19] [--grid] [--dry-run]
#
# 三种定位方式:
#   --auto            用 ffmpeg cropdetect 自动找内容区（**只在有黑边/留白时有用**）
#   --zoom 1.5        按倍数居中裁（--cx/--cy 用 0–1 指定中心，默认正中）
#   --crop W:H:X:Y    自己量好的精确矩形
#
#   --grid            不出片，只导一张带坐标网格的样帧到 <out>.grid.png，
#                     让你（或人类）看着挑坐标 —— agent 看不见画面，这是唯一靠谱的量法
#
# 常用倍数（来自真实交付）:
#   1.5×  常规放大，整页内容
#   2.0×  特写（对话框、评分圆环这类小元素）
set -euo pipefail
FF=${FF:-ffmpeg}; FP=${FP:-ffprobe}

SRC="${1:-}"; OUT="${2:-}"; shift 2 2>/dev/null || true
[ -n "$SRC" ] && [ -f "$SRC" ] && [ -n "$OUT" ] || { sed -n '2,22p' "$0"; exit 2; }

DUR=""; SS=0; MODE=""; ZOOM=1.5; CX=0.5; CY=0.5; CROP=""
OW=1080; OH=1920; FPS=30; CRF=19; GRID=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dur) DUR="$2"; shift 2;;
    --ss) SS="$2"; shift 2;;
    --auto) MODE=auto; shift;;
    --zoom) MODE=zoom; ZOOM="$2"; shift 2;;
    --cx) CX="$2"; shift 2;;
    --cy) CY="$2"; shift 2;;
    --crop) MODE=crop; CROP="$2"; shift 2;;
    --out-w) OW="$2"; shift 2;;
    --out-h) OH="$2"; shift 2;;
    --fps) FPS="$2"; shift 2;;
    --crf) CRF="$2"; shift 2;;
    --grid) GRID=1; shift;;
    --dry-run) DRY=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

IFS=',' read -r SW SH < <("$FP" -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$SRC")
SDUR=$("$FP" -v error -show_entries format=duration -of csv=p=0 "$SRC")

# ---- --grid：导一张带坐标网格的样帧，供人眼挑裁切框 ----
if [ "$GRID" = 1 ]; then
  G="${OUT%.*}.grid.png"
  mkdir -p "$(dirname "$G")"
  # 每 1/10 画幅画一条线，左上角标出源画幅
  step_x=$((SW / 10)); step_y=$((SH / 10))
  "$FF" -nostdin -y -v error -ss "$SS" -i "$SRC" -frames:v 1 -vf \
    "drawgrid=width=${step_x}:height=${step_y}:thickness=2:color=cyan@0.7,\
drawtext=text='${SW}x${SH}  grid=${step_x}x${step_y}  ss=${SS}':x=16:y=16:fontsize=28:fontcolor=yellow:box=1:boxcolor=black@0.6:boxborderw=8" \
    "$G" 2>/dev/null || "$FF" -nostdin -y -v error -ss "$SS" -i "$SRC" -frames:v 1 \
      -vf "drawgrid=width=${step_x}:height=${step_y}:thickness=2:color=cyan@0.7" "$G"
  echo "网格样帧 → $G   （源 ${SW}x${SH}，每格 ${step_x}x${step_y}）"
  echo "数格子定位后用：--crop W:H:X:Y"
  exit 0
fi

[ -n "$DUR" ] || { echo "需要 --dur <秒>" >&2; exit 2; }
[ -n "$MODE" ] || MODE=zoom

avail=$(awk -v d="$SDUR" -v s="$SS" 'BEGIN{printf "%.2f", d-s}')
awk -v a="$avail" -v d="$DUR" 'BEGIN{exit !(a >= d-0.05)}' || {
  echo "✗ 素材不够长：从 ${SS}s 起只剩 ${avail}s，这一拍要 ${DUR}s" >&2; exit 4; }

case "$MODE" in
  auto)
    # cropdetect 只能找「黑边/留白」。移动端满帧录屏本来就没有黑边，会原样返回全画幅。
    DET=$("$FF" -v info -ss "$SS" -i "$SRC" -vf "cropdetect=limit=24:round=2:reset=0" \
          -frames:v 60 -f null - 2>&1 | awk '/crop=/{c=$NF} END{print c}')
    CROP="${DET#crop=}"
    [ -n "$CROP" ] || { echo "cropdetect 没给出结果，改用 --zoom 或 --crop" >&2; exit 5; }
    if [ "$CROP" = "${SW}:${SH}:0:0" ]; then
      echo "  ○ cropdetect 返回整幅 —— 这条录屏没有黑边可裁（移动端满帧录屏就是这样）。"
      echo "    想放大就用 --zoom（按意图裁），别指望自动检测。"
    fi
    ;;
  zoom)
    read -r CW CH CXP CYP < <(awk -v sw="$SW" -v sh="$SH" -v z="$ZOOM" -v cx="$CX" -v cy="$CY" 'BEGIN{
      w=int(sw/z/2)*2; h=int(sh/z/2)*2;
      x=int(sw*cx - w/2); y=int(sh*cy - h/2);
      if(x<0)x=0; if(y<0)y=0;
      if(x+w>sw)x=sw-w; if(y+h>sh)y=sh-h;
      printf "%d %d %d %d\n", w,h,x,y }')
    CROP="${CW}:${CH}:${CXP}:${CYP}"
    ;;
  crop) : ;;
esac

IFS=':' read -r CW CH CXP CYP <<<"$CROP"
CXP=${CXP:-0}; CYP=${CYP:-0}
awk -v w="$CW" -v h="$CH" -v x="$CXP" -v y="$CYP" -v sw="$SW" -v sh="$SH" \
  'BEGIN{exit !(x>=0 && y>=0 && x+w<=sw && y+h<=sh)}' \
  || { echo "✗ 裁切框 ${CROP} 超出源画幅 ${SW}x${SH}" >&2; exit 6; }

UP=$(awk -v cw="$CW" -v ow="$OW" 'BEGIN{printf "%.2f", ow/cw}')
SHARP=""
awk -v u="$UP" 'BEGIN{exit !(u>1.0)}' && SHARP=",unsharp=5:5:0.6"

echo "源 ${SW}x${SH} (${SDUR}s) → crop ${CROP} → ${OW}x${OH} / ${DUR}s   放大 ${UP}×"
awk -v u="$UP" 'BEGIN{exit !(u>2.0)}' && echo "  ⚠ 放大 ${UP}× —— 会糊，提高录制分辨率或少裁一点" >&2

[ "$DRY" = 1 ] && exit 0

mkdir -p "$(dirname "$OUT")"
"$FF" -nostdin -y -v error -ss "$SS" -t "$DUR" -i "$SRC" \
  -vf "fps=${FPS},crop=${CROP},scale=${OW}:${OH}:flags=lanczos${SHARP},setsar=1,format=yuv420p" \
  -an -c:v libx264 -crf "$CRF" -pix_fmt yuv420p "$OUT"

GW=$("$FP" -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$OUT")
GH=$("$FP" -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$OUT")
GD=$("$FP" -v error -show_entries format=duration -of csv=p=0 "$OUT")
[ "$GW" = "$OW" ] && [ "$GH" = "$OH" ] || { echo "✗ 输出 ${GW}x${GH} ≠ ${OW}x${OH}" >&2; exit 7; }
printf '  ✓ %s  %sx%s  %.2fs\n' "$OUT" "$GW" "$GH" "$GD"
