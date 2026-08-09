#!/usr/bin/env bash
# verify-audio.sh — 配音自检：每句都存在、非空、时长合理、不是纯静音。
# TTS 失败会写出 0 字节或极短文件，后面 concat 会悄悄少一拍，必须先拦住。
# 用法: verify-audio.sh <audio-dir> <clips.json> [--min 0.8] [--max 20]
set -uo pipefail
FP=${FP:-ffprobe}
DIR="${1:-}"; CLIPS="${2:-}"; shift 2 2>/dev/null || true
[ -d "${DIR:-}" ] && [ -f "${CLIPS:-}" ] || { echo "用法: verify-audio.sh <audio-dir> <clips.json>" >&2; exit 2; }
MIN=0.8; MAX=20
while [ $# -gt 0 ]; do
  case "$1" in
    --min) MIN="$2"; shift 2;;
    --max) MAX="$2"; shift 2;;
    *) shift;;
  esac
done

fail=0; total=0
while IFS=$'\t' read -r name chars; do
  [ -n "$name" ] || continue
  f="$DIR/$name.mp3"
  if [ ! -s "$f" ]; then printf '  ✗ %s 缺失或 0 字节\n' "$name"; fail=1; continue; fi
  d=$($FP -v error -show_entries format=duration -of csv=p=0 "$f" 2>/dev/null)
  [ -n "$d" ] || { printf '  ✗ %s 不是合法音频\n' "$name"; fail=1; continue; }
  # volumedetect 的统计走 info 级日志 —— 这里绝不能用 -v error，否则输出被吞、误判成静音
  mv=$(ffmpeg -hide_banner -nostats -i "$f" -af volumedetect -f null - 2>&1 \
       | awk -F': ' '/max_volume/{print $2}' | awk '{print $1}')
  [ -n "$mv" ] || mv=0    # 解析不到就别瞎判静音
  msg=$(awk -v d="$d" -v mn="$MIN" -v mx="$MAX" -v c="${chars:-0}" -v v="$mv" 'BEGIN{
    s="";
    if (d<mn) s=s" 过短("d"s)";
    if (d>mx) s=s" 过长("d"s)";
    if (v<-45) s=s" 疑似静音(max_volume="v"dB)";
    if (c>0) { r=c/d; if (r<2.5) s=s sprintf(" 语速偏慢(%.1f字/秒)", r); if (r>8) s=s sprintf(" 语速偏快(%.1f字/秒)", r) }
    print s }')
  total=$(awk -v t="$total" -v d="$d" 'BEGIN{printf "%.2f", t+d}')
  if [ -n "$msg" ]; then printf '  ✗ %s%s\n' "$name" "$msg"; fail=1
  else printf '  ✓ %s  %.2fs\n' "$name" "$d"; fi
done < <(python3 -c '
import json,sys
for c in json.load(open(sys.argv[1])): print(c["name"] + "\t" + str(len(c.get("text",""))))
' "$CLIPS")

printf '  配音总时长 %ss\n' "$total"
[ "$fail" = 0 ] && { echo "  ALL OK"; exit 0; } || { echo "  FAILED"; exit 1; }
