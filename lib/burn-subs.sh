#!/usr/bin/env bash
# burn-subs.sh — 把 gen-subs.py / gen-callouts.py 产出的 PNG 序列按时间窗 overlay 到成片上
# （保留原音轨）。不需要 libass。
#
# 用法: burn-subs.sh <in.mp4> <out.mp4> [--manifest subs/manifest.tsv] [--crf 19]
#
# --manifest 可以给**多次**，一次压多层、只编码一遍：
#   burn-subs.sh in.mp4 out.mp4 --manifest subs/manifest.tsv --manifest callouts/manifest.tsv
# 顺序 = 图层顺序，后给的画在上面。字幕在底、标注在中上，两层不打架。
set -euo pipefail
FF=${FF:-ffmpeg}; FP=${FP:-ffprobe}
IN="${1:-}"; OUT="${2:-}"; shift 2 2>/dev/null || true
[ -f "${IN:-}" ] && [ -n "${OUT:-}" ] || { echo "用法: burn-subs.sh <in.mp4> <out.mp4> [--manifest ...]" >&2; exit 2; }
MANS=(); CRF=19
while [ $# -gt 0 ]; do
  case "$1" in
    --manifest) MANS+=("$2"); shift 2;;
    --crf) CRF="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ ${#MANS[@]} -gt 0 ] || MANS=("$(dirname "$IN")/subs/manifest.tsv")
for m in "${MANS[@]}"; do
  [ -f "$m" ] || { echo "manifest 不存在: ${m}（先跑 lib/gen-subs.py 或 lib/gen-callouts.py）" >&2; exit 2; }
done

V="fps=30,setsar=1,format=yuv420p"
inputs=(-i "$IN"); fc=""; prev="0:v"; i=1
for m in "${MANS[@]}"; do
  while IFS=$'\t' read -r png s e; do
    [ -n "${png:-}" ] || continue
    [ -f "$png" ] || { echo "叠加图不存在: $png" >&2; exit 3; }
    inputs+=(-i "$png")
    fc+="[$prev][$i:v]overlay=0:0:enable='between(t,$s,$e)'[v$i];"
    prev="v$i"; i=$((i+1))
  done < "$m"
done
[ "$i" -gt 1 ] || { echo "manifest 是空的" >&2; exit 3; }
fc+="[$prev]$V[vout]"

# 有音轨就带上，没有就只出视频（-map 0:a? 里的 ? = optional）
"$FF" -nostdin -y -v error "${inputs[@]}" -filter_complex "$fc" \
  -map "[vout]" -map 0:a? -c:v libx264 -crf "$CRF" -pix_fmt yuv420p -c:a copy \
  -movflags +faststart "$OUT"

echo "burned $((i-1)) overlays（${#MANS[@]} 层）-> $OUT  ($($FP -v error -show_entries format=duration -of csv=p=0 "$OUT")s)"
