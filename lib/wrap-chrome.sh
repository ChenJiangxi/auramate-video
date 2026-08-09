#!/usr/bin/env bash
# wrap-chrome.sh — 把录屏套进假浏览器壳：chrome 条在上，内容在下，vstack 成一整帧。
#
# 用法:
#   wrap-chrome.sh <src> <out> --chrome <chrome.png> --dur <秒>
#        [--ss <起始秒>] [--crop W:H:X:Y] [--out-w 1920] [--out-h 1080]
#        [--fps 30] [--crf 19] [--freeze] [--dry-run]
#
#   --crop    内容区裁切框（不给就自动按目标宽高比居中裁）
#   --freeze  源比这一拍短时，冻结末帧补足（tpad），而不是直接报错
#
# 两个必须的保护（都真炸过）:
#   · `-loop 1 -i chrome.png` **必须**配 `-t`，否则 ffmpeg 无限读那张图，编码永不结束
#     （真实记录：单个 clip 卡到 67 分钟 CPU）
#   · 内容高度 = 目标高 - chrome 高，两块 vstack 之后才等于目标画幅
set -euo pipefail
FF=${FF:-ffmpeg}; FP=${FP:-ffprobe}

SRC="${1:-}"; OUT="${2:-}"; shift 2 2>/dev/null || true
[ -n "$SRC" ] && [ -f "$SRC" ] && [ -n "$OUT" ] || { sed -n '2,18p' "$0"; exit 2; }

CHROME=""; DUR=""; SS=0; CROP=""; OW=1920; OH=1080; FPS=30; CRF=19; FREEZE=0; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --chrome) CHROME="$2"; shift 2;;
    --dur) DUR="$2"; shift 2;;
    --ss) SS="$2"; shift 2;;
    --crop) CROP="$2"; shift 2;;
    --out-w) OW="$2"; shift 2;;
    --out-h) OH="$2"; shift 2;;
    --fps) FPS="$2"; shift 2;;
    --crf) CRF="$2"; shift 2;;
    --freeze) FREEZE=1; shift;;
    --dry-run) DRY=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$CHROME" ] && [ -f "$CHROME" ] || { echo "需要 --chrome <chrome.png>（用 lib/browser-chrome.py 生成）" >&2; exit 2; }
[ -n "$DUR" ] || { echo "需要 --dur <秒>" >&2; exit 2; }

IFS=',' read -r SW SH < <("$FP" -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$SRC")
IFS=',' read -r CBW CBH < <("$FP" -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$CHROME")
SDUR=$("$FP" -v error -show_entries format=duration -of csv=p=0 "$SRC")

# chrome 条按目标宽等比缩放，内容填剩下的高度
BARH=$(awk -v w="$OW" -v cw="$CBW" -v ch="$CBH" 'BEGIN{printf "%d", int(ch*w/cw/2)*2}')
CONH=$((OH - BARH))
[ "$CONH" -gt 0 ] || { echo "✗ chrome 条 ${BARH}px 比目标高 ${OH}px 还高" >&2; exit 3; }

# 没给裁切框就按内容区宽高比居中裁
if [ -z "$CROP" ]; then
  read -r CW CH CX CY < <(awk -v sw="$SW" -v sh="$SH" -v ow="$OW" -v oh="$CONH" 'BEGIN{
    tar=ow/oh; src=sw/sh;
    if (src > tar) { h=sh; w=int(h*tar/2)*2 } else { w=sw; h=int(w/tar/2)*2 }
    if(w>sw)w=int(sw/2)*2; if(h>sh)h=int(sh/2)*2;
    printf "%d %d %d %d\n", w, h, int((sw-w)/2), int((sh-h)/2) }')
  CROP="${CW}:${CH}:${CX}:${CY}"
fi
IFS=':' read -r CW CH CX CY <<<"$CROP"
awk -v w="$CW" -v h="$CH" -v x="$CX" -v y="$CY" -v sw="$SW" -v sh="$SH" \
  'BEGIN{exit !(x>=0 && y>=0 && x+w<=sw && y+h<=sh)}' \
  || { echo "✗ 裁切框 ${CROP} 超出源画幅 ${SW}x${SH}" >&2; exit 4; }

avail=$(awk -v d="$SDUR" -v s="$SS" 'BEGIN{printf "%.2f", d-s}')
if ! awk -v a="$avail" -v d="$DUR" 'BEGIN{exit !(a >= d-0.05)}'; then
  [ "$FREEZE" = 1 ] || { echo "✗ 素材不够长：从 ${SS}s 起只剩 ${avail}s，这一拍要 ${DUR}s（加 --freeze 冻结末帧补足）" >&2; exit 5; }
  echo "  ! 素材只有 ${avail}s，用 --freeze 冻结末帧补到 ${DUR}s"
fi
PAD=""
[ "$FREEZE" = 1 ] && PAD="tpad=stop_mode=clone:stop_duration=${DUR},"

UP=$(awk -v cw="$CW" -v ow="$OW" 'BEGIN{printf "%.2f", ow/cw}')
SHARP=""
awk -v u="$UP" 'BEGIN{exit !(u>1.0)}' && SHARP=",unsharp=5:5:0.6"

echo "源 ${SW}x${SH} → crop ${CROP} → 内容 ${OW}x${CONH} + 壳 ${OW}x${BARH} = ${OW}x${OH} / ${DUR}s  放大 ${UP}×"
[ "$DRY" = 1 ] && exit 0

mkdir -p "$(dirname "$OUT")"
# -loop 1 的那一路必须带 -t，否则永远编不完
"$FF" -nostdin -y -v error -ss "$SS" -t "$DUR" -i "$SRC" -loop 1 -t "$DUR" -i "$CHROME" \
  -filter_complex "\
[0:v]fps=${FPS},crop=${CROP},scale=${OW}:${CONH}:flags=lanczos${SHARP},${PAD}trim=duration=${DUR},setpts=PTS-STARTPTS[content];\
[1:v]fps=${FPS},scale=${OW}:${BARH},trim=duration=${DUR},setpts=PTS-STARTPTS[bar];\
[bar][content]vstack=inputs=2,setsar=1,format=yuv420p[v]" \
  -map "[v]" -an -c:v libx264 -crf "$CRF" -pix_fmt yuv420p "$OUT"

GW=$("$FP" -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$OUT")
GH=$("$FP" -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$OUT")
GD=$("$FP" -v error -show_entries format=duration -of csv=p=0 "$OUT")
[ "$GW" = "$OW" ] && [ "$GH" = "$OH" ] || { echo "✗ 输出 ${GW}x${GH} ≠ ${OW}x${OH}" >&2; exit 6; }
printf '  ✓ %s  %sx%s  %.2fs\n' "$OUT" "$GW" "$GH" "$GD"
