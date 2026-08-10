#!/usr/bin/env bash
# build-vertical.sh — audio-driven 竖版短视频合成（1080×1920 / 30fps）
#
# 用法:
#   build-vertical.sh --project <dir> [--shots shots.tsv] [--out out.mp4]
#                     [--gap 0.25] [--gain 4dB] [--w 1080] [--h 1920] [--fps 30] [--crf 19]
#
# 输入:
#   <project>/clips.json   [{"name":"c01","text":"..."}, ...]   ← 顺序即成片顺序
#   <project>/audio/<name>.mp3                                   ← 每句配音，时长驱动时间轴
#   <project>/<shots.tsv>  clip <TAB> 编码器 <TAB> 素材路径 <TAB> 起始秒 [<TAB> 额外参数]
#
# 编码器:
#   card   静态卡/已竖版渲染物 —— 直接 scale 铺满
#   full   竖版录屏/竖版素材   —— scale + unsharp 锐化（**不限制放大倍数**，源要够清晰）
#   fit    不确定源多大就用它 —— 转交 fit-vertical.sh，自动限制放大倍数防糊
#   motion 带镜头运动的录屏 —— 转交 motion.sh，第5列写它的参数，例如
#          "--move punch-in --to 620:900:50:260"（产品演示片的主力，静态框字读不清）
#   celeb  横屏真人切片        —— 模糊背景垫底 + 主体等比居中
#   patch  录屏 + 图片补丁     —— 第5列 = "补丁图:x:y:crop_w:crop_h:crop_x:pad_y"
#
# 产物: <project>/work/vNN.mp4 · work/video.mp4 · work/voice.m4a · <out>
set -euo pipefail

HERE_LIB="$(cd "$(dirname "$0")" && pwd)"
PROJECT=""; SHOTS="shots.tsv"; OUT=""; GAP=0.25; GAIN="4dB"
W=1080; H=1920; FPS=30; CRF=19; MAXUP=1.6
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --shots)   SHOTS="$2";   shift 2;;
    --out)     OUT="$2";     shift 2;;
    --gap)     GAP="$2";     shift 2;;
    --gain)    GAIN="$2";    shift 2;;
    --w)       W="$2";       shift 2;;
    --h)       H="$2";       shift 2;;
    --fps)     FPS="$2";     shift 2;;
    --crf)     CRF="$2";     shift 2;;
    --max-upscale) MAXUP="$2"; shift 2;;   # 只影响 fit 编码器
    -h|--help) sed -n '2,25p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$PROJECT" ] || { echo "need --project <dir>" >&2; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd)"
[ -f "$PROJECT/clips.json" ] || { echo "missing $PROJECT/clips.json" >&2; exit 2; }
# --shots：先按当前工作目录解，解不到再按项目目录解（默认值 shots.tsv 指的是项目内）
case "$SHOTS" in
  /*) ;;
  *) if [ -f "$PWD/$SHOTS" ]; then SHOTS="$PWD/$SHOTS"; else SHOTS="$PROJECT/$SHOTS"; fi;;
esac
[ -f "$SHOTS" ] || { echo "missing shots file: $SHOTS" >&2; exit 2; }
# --out：相对路径按**当前工作目录**解，这是 CLI 的常规语义。
# （曾经错误地按项目目录解 → 从 repo 根传 examples/x/out.mp4 会拼成
#   examples/x/examples/x/out.mp4，ffmpeg 报 No such file or directory）
[ -n "$OUT" ] || OUT="$PROJECT/out-nosub.mp4"
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT";; esac

FF=${FF:-ffmpeg}; FP=${FP:-ffprobe}
command -v "$FF" >/dev/null || { echo "ffmpeg not found" >&2; exit 3; }
command -v "$FP" >/dev/null || { echo "ffprobe not found" >&2; exit 3; }

WORK="$PROJECT/work"; mkdir -p "$WORK"
V="fps=${FPS},setsar=1,format=yuv420p"

dur(){ "$FP" -v error -show_entries format=duration -of csv=p=0 "$1"; }
fadd(){ awk -v a="$1" -v b="$2" 'BEGIN{printf "%.3f", a+b}'; }

# ---- 读 clips.json 的 name 顺序（不依赖 jq；兼容 bash 3.2，不用 mapfile）----
CLIPS=()
while IFS= read -r _n; do [ -n "$_n" ] && CLIPS+=("$_n"); done < <(python3 -c '
import json,sys
for c in json.load(open(sys.argv[1])): print(c["name"])
' "$PROJECT/clips.json")
[ "${#CLIPS[@]}" -gt 0 ] || { echo "clips.json 里没有 clip" >&2; exit 2; }

echo "[1/5] 量配音时长（audio-driven，GAP=${GAP}s）"
declare -a TS=() ADUR=()
for name in "${CLIPS[@]}"; do
  a="$PROJECT/audio/$name.mp3"
  [ -s "$a" ] || { echo "  ✗ 缺配音或空文件: $a" >&2; exit 4; }
  d="$(dur "$a")"
  ADUR+=("$d"); TS+=("$(fadd "$d" "$GAP")")
  printf "  %s  voice=%.3fs  shot=%.3fs\n" "$name" "$d" "$(fadd "$d" "$GAP")"
done

# ---- 读 shots.tsv ----
declare -a KIND=() SRC=() SS=() EXTRA=()
for name in "${CLIPS[@]}"; do
  line="$(awk -F'\t' -v n="$name" '$1==n{print; exit}' "$SHOTS")"
  [ -n "$line" ] || { echo "  ✗ shots.tsv 里没有 $name" >&2; exit 4; }
  k="$(printf '%s' "$line" | cut -f2)"
  s="$(printf '%s' "$line" | cut -f3)"
  t="$(printf '%s' "$line" | cut -f4)"; [ -n "$t" ] || t=0
  x="$(printf '%s' "$line" | cut -f5)"
  case "$s" in /*) ;; *) s="$PROJECT/$s";; esac
  [ -f "$s" ] || { echo "  ✗ 素材不存在: $s ($name)" >&2; exit 4; }
  KIND+=("$k"); SRC+=("$s"); SS+=("$t"); EXTRA+=("$x")
done

echo "[2/5] 逐拍编码"
enc_card(){ "$FF" -nostdin -y -v error -i "$1" -t "$2" \
  -vf "scale=${W}:${H}:flags=lanczos,$V" -an -c:v libx264 -crf "$CRF" -pix_fmt yuv420p "$3"; }

enc_full(){ "$FF" -nostdin -y -v error -ss "$4" -t "$2" -i "$1" \
  -vf "scale=${W}:${H}:flags=lanczos,unsharp=7:7:0.9,$V" -an -c:v libx264 -crf "$CRF" -pix_fmt yuv420p "$3"; }

# 低分辨率源用 full 会闷头拉满、糊得没法看。fit 交给 fit-vertical.sh，
# 它按 --max-upscale 自动决定「铺满」还是「模糊垫底 + 前景保持清晰」。
# 注意：别把 fit-vertical 的输出直接管道给带 exit 的 awk —— awk 提前退出会给上游
# 发 SIGPIPE，配合 set -o pipefail + set -e 会把整个 build 静默干掉（踩过）。
# 先整段收进变量，再在变量上做提取。
# 镜头运动：第5列原样当参数传给 motion.sh
enc_motion(){
  local out
  # shellcheck disable=SC2086
  out="$("$HERE_LIB/motion.sh" "$1" "$3" --dur "$2" --ss "$4" \
           --out-w "$W" --out-h "$H" --fps "$FPS" --crf "$CRF" ${5:-} 2>&1)" || {
    echo "$out" >&2; return 1; }
  FITNOTE="$(printf '%s\n' "$out" | grep -m1 '→' | sed 's/^ *//')"
}

enc_fit(){
  local out
  out="$("$HERE_LIB/fit-vertical.sh" "$1" "$3" --dur "$2" --ss "$4" \
           --w "$W" --h "$H" --fps "$FPS" --crf "$CRF" --max-upscale "$MAXUP" 2>&1)" || {
    echo "$out" >&2; return 1; }
  FITNOTE="$(printf '%s\n' "$out" | grep -m1 'mode=' | sed 's/^ *//')"
}

enc_celeb(){ "$FF" -nostdin -y -v error -ss "$4" -t "$2" -i "$1" -vf \
  "split=2[a][b];[a]scale=${W}:${H}:force_original_aspect_ratio=increase,crop=${W}:${H},boxblur=26:3,eq=brightness=-0.34:saturation=0.66[bg];[b]scale=${W}:$(( H * 43 / 100 )):force_original_aspect_ratio=decrease,unsharp=5:5:0.6[fg];[bg][fg]overlay=(W-w)/2:$(( H * 23 / 100 )),$V" \
  -an -c:v libx264 -crf "$CRF" -pix_fmt yuv420p "$3"; }

# EXTRA 格式: 补丁图:ox:oy:cw:ch:cx:pady
enc_patch(){
  local src="$1" t="$2" out="$3" ss="$4" spec="$5"
  local img ox oy cw ch cx pady
  IFS=: read -r img ox oy cw ch cx pady <<<"$spec"
  case "$img" in /*) ;; *) img="$PROJECT/$img";; esac
  [ -f "$img" ] || { echo "  ✗ 补丁图不存在: $img" >&2; return 1; }
  "$FF" -nostdin -y -v error -ss "$ss" -t "$t" -i "$src" -i "$img" \
    -filter_complex "[0:v][1:v]overlay=${ox}:${oy}[p];[p]crop=${cw}:${ch}:${cx}:0,pad=${W}:${H}:0:${pady},unsharp=5:5:0.6,$V[v]" \
    -map "[v]" -an -c:v libx264 -crf "$CRF" -pix_fmt yuv420p "$out"
}

: > "$WORK/vl.txt"
i=0
for name in "${CLIPS[@]}"; do
  idx="$(printf '%02d' $((i+1)))"
  o="$WORK/v$idx.mp4"
  case "${KIND[$i]}" in
    card)  enc_card  "${SRC[$i]}" "${TS[$i]}" "$o";;
    full)  enc_full  "${SRC[$i]}" "${TS[$i]}" "$o" "${SS[$i]}";;
    fit)   enc_fit   "${SRC[$i]}" "${TS[$i]}" "$o" "${SS[$i]}";;
    motion) enc_motion "${SRC[$i]}" "${TS[$i]}" "$o" "${SS[$i]}" "${EXTRA[$i]}";;
    celeb) enc_celeb "${SRC[$i]}" "${TS[$i]}" "$o" "${SS[$i]}";;
    patch) enc_patch "${SRC[$i]}" "${TS[$i]}" "$o" "${SS[$i]}" "${EXTRA[$i]}";;
    *) echo "  ✗ 未知编码器 '${KIND[$i]}' ($name)" >&2; exit 4;;
  esac
  got="$(dur "$o")"
  awk -v a="$got" -v b="${TS[$i]}" 'BEGIN{ if ((a-b)>0.15 || (b-a)>0.15) exit 1 }' \
    || echo "  ⚠ $name 实际 ${got}s ≠ 目标 ${TS[$i]}s（素材可能比这拍短）" >&2
  # 清晰度账：源比目标窄多少就要放大多少。fit 编码器会自己封顶，所以不按这个口径警告。
  sw="$("$FP" -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "${SRC[$i]}" 2>/dev/null | head -1)"
  up="$(awk -v s="${sw:-0}" -v w="$W" 'BEGIN{ if (s>0) printf "%.2f", w/s; else print "?" }')"
  if [ "${KIND[$i]}" = fit ] || [ "${KIND[$i]}" = motion ]; then
    printf "  %s  %-5s  %ss  源宽%s  %s\n" "$name" "${KIND[$i]}" "$got" "${sw:-?}" "${FITNOTE:-已封顶}"
  else
    mark="$(awk -v u="${up}" 'BEGIN{ if (u=="?") print ""; else if (u>2.0) print "  ✗ 太糊，换高分辨率源（或改用 fit 编码器）"; else if (u>1.3) print "  ⚠ 偏糊（可改用 fit）"; else print "" }')"
    [ -n "$mark" ] && echo "  ⚠ $name 源宽 ${sw}px → 放大 ${up}×${mark}" >&2
    printf "  %s  %-5s  %ss  源宽%s 放大%s×\n" "$name" "${KIND[$i]}" "$got" "${sw:-?}" "$up"
  fi
  echo "file '$o'" >> "$WORK/vl.txt"
  i=$((i+1))
done

echo "[3/5] concat 视频"
"$FF" -nostdin -y -v error -f concat -safe 0 -i "$WORK/vl.txt" \
  -c:v libx264 -crf "$CRF" -pix_fmt yuv420p "$WORK/video.mp4"
echo "  video $(dur "$WORK/video.mp4")s"

echo "[4/5] 拼音轨（每句 apad 到本拍时长，防漂移）"
ain=(); fc=""; n=0
for name in "${CLIPS[@]}"; do
  ain+=(-i "$PROJECT/audio/$name.mp3")
  fc+="[${n}:a]aresample=44100,volume=${GAIN},apad,atrim=0:${TS[$n]}[a${n}];"
  n=$((n+1))
done
for ((k=0;k<n;k++)); do fc+="[a${k}]"; done
fc+="concat=n=${n}:v=0:a=1[a]"
"$FF" -nostdin -y -v error "${ain[@]}" -filter_complex "$fc" -map "[a]" "$WORK/voice.m4a"
echo "  voice $(dur "$WORK/voice.m4a")s"

echo "[5/5] mux"
"$FF" -nostdin -y -v error -i "$WORK/video.mp4" -i "$WORK/voice.m4a" \
  -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart "$OUT"

echo "=== RESULT ==="
"$FP" -v error -show_entries format=duration:stream=width,height,codec_name \
  -of default=noprint_wrappers=1 "$OUT"
du -h "$OUT" | cut -f1
