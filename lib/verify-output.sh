#!/usr/bin/env bash
# verify-output.sh — 成片机械自检。报错就别交付。
# 用法: verify-output.sh <video.mp4> [--expect-w 1080] [--expect-h 1920]
#                        [--min-dur 55] [--max-dur 95] [--fps 30] [--require-audio]
set -uo pipefail
FP=${FP:-ffprobe}
VID="${1:-}"; shift || true
[ -n "$VID" ] && [ -f "$VID" ] || { echo "用法: verify-output.sh <video.mp4> [...]" >&2; exit 2; }
EW=1080; EH=1920; MIND=""; MAXD=""; EFPS=""; REQA=1
while [ $# -gt 0 ]; do
  case "$1" in
    --expect-w) EW="$2"; shift 2;;
    --expect-h) EH="$2"; shift 2;;
    --min-dur)  MIND="$2"; shift 2;;
    --max-dur)  MAXD="$2"; shift 2;;
    --fps)      EFPS="$2"; shift 2;;
    --require-audio) REQA=1; shift;;
    --no-audio) REQA=0; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

fail=0
ok(){   printf '  ✓ %s\n' "$1"; }
bad(){  printf '  ✗ %s\n' "$1"; fail=1; }

W=$($FP -v error -select_streams v:0 -show_entries stream=width  -of csv=p=0 "$VID" | head -1)
H=$($FP -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$VID" | head -1)
D=$($FP -v error -show_entries format=duration -of csv=p=0 "$VID")
RFR=$($FP -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$VID" | head -1)
ACODEC=$($FP -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$VID" | head -1)
VCODEC=$($FP -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$VID" | head -1)

echo "== $VID"
printf '  %sx%s  %.2fs  v=%s a=%s  fps=%s\n' "$W" "$H" "$D" "${VCODEC:-none}" "${ACODEC:-none}" "$RFR"

[ "$W" = "$EW" ] && [ "$H" = "$EH" ] && ok "分辨率 ${EW}×${EH}" || bad "分辨率 ${W}×${H}，期望 ${EW}×${EH}"
[ -n "$VCODEC" ] && ok "有视频流 ($VCODEC)" || bad "没有视频流"

if [ "$REQA" = 1 ]; then
  [ -n "$ACODEC" ] && ok "有音频流 ($ACODEC)" || bad "没有音频流"
fi

if [ -n "$MIND" ]; then
  awk -v d="$D" -v m="$MIND" 'BEGIN{exit !(d>=m)}' && ok "时长 ≥ ${MIND}s" || bad "时长 ${D}s < ${MIND}s"
fi
if [ -n "$MAXD" ]; then
  awk -v d="$D" -v m="$MAXD" 'BEGIN{exit !(d<=m)}' && ok "时长 ≤ ${MAXD}s" || bad "时长 ${D}s > ${MAXD}s"
fi
if [ -n "$EFPS" ]; then
  awk -v r="$RFR" -v e="$EFPS" 'BEGIN{split(r,p,"/"); f=(p[2]?p[1]/p[2]:p[1]); exit !(f>e-0.5 && f<e+0.5)}' \
    && ok "帧率 ≈ ${EFPS}" || bad "帧率 ${RFR}，期望 ${EFPS}"
fi

# faststart: moov 应该在文件前部
if command -v python3 >/dev/null; then
  python3 - "$VID" <<'PY' && ok "moov 在文件前部 (+faststart)" || bad "moov 在文件尾部 —— 导出漏了 -movflags +faststart"
import sys,struct
p=sys.argv[1]
with open(p,'rb') as f:
    off=0
    while True:
        hdr=f.read(8)
        if len(hdr)<8: sys.exit(1)
        size=struct.unpack('>I',hdr[:4])[0]; typ=hdr[4:8]
        if size==1:
            size=struct.unpack('>Q',f.read(8))[0]; f.seek(size-16,1)
        elif size==0:
            sys.exit(1 if typ!=b'moov' else 0)
        else:
            f.seek(size-8,1)
        if typ==b'moov': sys.exit(0)
        if typ==b'mdat': sys.exit(1)
PY
fi

[ "$fail" = 0 ] && { echo "  ALL OK"; exit 0; } || { echo "  FAILED"; exit 1; }
