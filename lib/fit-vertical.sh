#!/usr/bin/env bash
# fit-vertical.sh — 把任意画幅的素材切一段、转成 1080×1920 竖版拍。
#
# 用法:
#   fit-vertical.sh <src> <out> --dur <秒> [--ss <起始秒>]
#        [--mode auto|blur|fill|pad] [--w 1080] [--h 1920] [--fps 30] [--crf 19]
#        [--max-upscale 2.5] [--fg-center 0.40] [--sub-top 1340] [--dry-run]
#
# mode:
#   auto  按源画幅自动选（默认，推荐）
#   blur  模糊背景垫底 + 主体等比居中 —— 横屏源转竖版的标准做法，保留源水印字幕=真实混剪质感
#   fill  等比放大铺满后裁切 —— 只适合本来就接近 9:16 的源
#   pad   主体居中 + 上下纯色边 —— "素材感"更强，但上下大片死区
#
# 关键约束（都是量真实素材量出来的，见 skills/real-clip-mashup/）:
#   · 前景放大倍数决定清晰度。降采样最锐；升采样必须补 unsharp。
#   · 前景底边不能压到字幕（默认字幕基线 1400，所以前景底边留在 1340 以上）。
#   · 前景视觉中心放在画面 40% 高度处，下方留给字幕。
set -euo pipefail

FF=${FF:-ffmpeg}; FP=${FP:-ffprobe}
SRC="${1:-}"; OUT="${2:-}"; shift 2 2>/dev/null || true
[ -n "$SRC" ] && [ -f "$SRC" ] && [ -n "$OUT" ] || {
  sed -n '2,20p' "$0"; exit 2; }

MODE=auto; W=1080; H=1920; FPS=30; CRF=19; DUR=""; SS=0
MAXUP=2.5; FGC=0.40; SUBTOP=1340; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --dur) DUR="$2"; shift 2;;
    --ss) SS="$2"; shift 2;;
    --mode) MODE="$2"; shift 2;;
    --w) W="$2"; shift 2;;
    --h) H="$2"; shift 2;;
    --fps) FPS="$2"; shift 2;;
    --crf) CRF="$2"; shift 2;;
    --max-upscale) MAXUP="$2"; shift 2;;
    --fg-center) FGC="$2"; shift 2;;
    --sub-top) SUBTOP="$2"; shift 2;;
    --dry-run) DRY=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$DUR" ] || { echo "需要 --dur <秒>（这一拍多长，由配音时长决定）" >&2; exit 2; }

read -r SW SH < <("$FP" -v error -select_streams v:0 -show_entries stream=width,height \
                   -of csv=p=0 "$SRC" | tr ',' ' ')
SDUR=$("$FP" -v error -show_entries format=duration -of csv=p=0 "$SRC")
[ -n "${SW:-}" ] && [ -n "${SH:-}" ] || { echo "读不到源画幅: $SRC" >&2; exit 3; }

AR=$(awk -v w="$SW" -v h="$SH" 'BEGIN{printf "%.4f", w/h}')

# 素材够不够长
avail=$(awk -v d="$SDUR" -v s="$SS" 'BEGIN{printf "%.2f", d-s}')
awk -v a="$avail" -v d="$DUR" 'BEGIN{exit !(a >= d-0.05)}' || {
  echo "✗ 素材不够长：从 ${SS}s 起只剩 ${avail}s，这一拍要 ${DUR}s" >&2
  echo "  → 换起始点 / 换素材 / 用 setpts 放慢（见 skills/ffmpeg-cookbook/）" >&2
  exit 4; }

# ---- auto 选模式 ----
if [ "$MODE" = auto ]; then
  fill_up=$(awk -v w="$SW" -v h="$SH" -v W="$W" -v H="$H" 'BEGIN{a=W/w;b=H/h;printf "%.3f", (a>b?a:b)}')
  if awk -v ar="$AR" 'BEGIN{exit !(ar < 0.85)}'; then
    # 竖版源：能不裁太多就铺满，放大过头就退回 blur
    if awk -v u="$fill_up" -v m="$MAXUP" 'BEGIN{exit !(u <= m)}'; then MODE=fill; else MODE=blur; fi
  else
    MODE=blur          # 横屏 / 方形一律 blur
  fi
fi

V="fps=${FPS},setsar=1,format=yuv420p"

case "$MODE" in
  blur)
    # 前景盒子：宽最多 W；再受 max-upscale 限制，避免把低分辨率源拉糊
    read -r FGW FGH FGY NOTE < <(awk -v sw="$SW" -v sh="$SH" -v W="$W" -v H="$H" \
        -v m="$MAXUP" -v c="$FGC" -v st="$SUBTOP" 'BEGIN{
      capw = sw*m; fgw = (capw < W ? capw : W);
      fgh = fgw*sh/sw;
      maxh = st - 60;                       # 顶部留 60，底边不越过字幕线
      if (fgh > maxh) { fgh = maxh; fgw = fgh*sw/sh }
      fgw = int(fgw/2)*2; fgh = int(fgh/2)*2;
      y = int(c*H - fgh/2); if (y < 60) y = 60;
      if (y + fgh > st) y = st - fgh;
      up = fgw/sw;
      printf "%d %d %d %.2f\n", fgw, fgh, y, up }')   # 末尾必须有 \n，否则 read 返回 1、set -e 直接把脚本干掉
    FILTER="split=2[a][b];\
[a]scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},boxblur=26:3,eq=brightness=-0.34:saturation=0.66[bg];\
[b]scale=${FGW}:${FGH}:force_original_aspect_ratio=decrease,unsharp=5:5:0.6[fg];\
[bg][fg]overlay=(W-w)/2:${FGY},${V}"
    DESC="blur 前景 ${FGW}x${FGH} @y=${FGY}，前景缩放 ${NOTE}×"
    UP="$NOTE"
    ;;
  fill)
    UP=$(awk -v w="$SW" -v h="$SH" -v W="$W" -v H="$H" 'BEGIN{a=W/w;b=H/h;printf "%.2f",(a>b?a:b)}')
    SHARP=""
    awk -v u="$UP" 'BEGIN{exit !(u>1.0)}' && SHARP="unsharp=5:5:0.6,"
    FILTER="scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},${SHARP}${V}"
    DESC="fill 铺满裁切，缩放 ${UP}×"
    ;;
  pad)
    PW=$(awk -v W="$W" 'BEGIN{printf "%d", int(W*0.963/2)*2}')   # 1080 → 1040
    UP=$(awk -v w="$SW" -v p="$PW" 'BEGIN{printf "%.2f", p/w}')
    FILTER="scale=${PW}:-2,pad=${W}:${H}:(ow-iw)/2:(oh-ih)/2:0x0a0a12,${V}"
    DESC="pad 居中 + 深色边，宽 ${PW}，缩放 ${UP}×"
    ;;
  *) echo "未知 mode: $MODE" >&2; exit 2;;
esac

echo "源 ${SW}x${SH} (AR ${AR}, ${SDUR}s) → ${W}x${H} / ${DUR}s"
echo "  mode=${MODE}  ${DESC}"
awk -v u="$UP" 'BEGIN{exit !(u>2.5)}' && echo "  ⚠ 前景放大 ${UP}× —— 超过 2.5 会明显糊，优先换高分辨率源" >&2
awk -v u="$UP" 'BEGIN{exit !(u>1.8 && u<=2.5)}' && echo "  ! 前景放大 ${UP}× —— 已加 unsharp，但换个源更好" >&2

[ "$DRY" = 1 ] && exit 0

mkdir -p "$(dirname "$OUT")"
"$FF" -nostdin -y -v error -ss "$SS" -t "$DUR" -i "$SRC" \
  -vf "$FILTER" -an -c:v libx264 -crf "$CRF" -pix_fmt yuv420p "$OUT"

GOTW=$("$FP" -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$OUT")
GOTH=$("$FP" -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$OUT")
GOTD=$("$FP" -v error -show_entries format=duration -of csv=p=0 "$OUT")
[ "$GOTW" = "$W" ] && [ "$GOTH" = "$H" ] || { echo "✗ 输出画幅 ${GOTW}x${GOTH} ≠ ${W}x${H}" >&2; exit 5; }
awk -v a="$GOTD" -v b="$DUR" 'BEGIN{exit !((a-b<0.2)&&(b-a<0.2))}' \
  || echo "  ⚠ 输出 ${GOTD}s 与目标 ${DUR}s 差得有点多" >&2
printf '  ✓ %s  %sx%s  %.2fs\n' "$OUT" "$GOTW" "$GOTH" "$GOTD"
