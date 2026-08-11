#!/usr/bin/env bash
# build-vertical.sh — audio-driven 竖版短视频合成（1080×1920 / 30fps）
#
# 用法:
#   build-vertical.sh --project <dir> [--shots shots.tsv] [--out out.mp4]
#                     [--gap 0.25] [--gain 4dB] [--w 1080] [--h 1920] [--fps 30] [--crf 19]
#                     [--xfade 0.22] [--xfade-type auto] [--no-xfade]
#
# 输入:
#   <project>/clips.json   [{"name":"c01","text":"..."}, ...]   ← 顺序即成片顺序
#   <project>/audio/<name>.mp3                                   ← 每句配音，时长驱动时间轴
#   <project>/<shots.tsv>  clip <TAB> 编码器 <TAB> 素材路径 <TAB> 起始秒 [<TAB> 额外参数]
#                          [<TAB> 画面说明] [<TAB> 入场转场]
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
# 转场（第7列，写的是「进入这一拍」用什么）:
#   cut          硬切
#   fade         叠化（默认）· fadeblack 闪黑 · dissolve 颗粒溶解
#   smoothup/slideup/circleopen/wipeup/pixelize …  xfade 支持的都能写
#   fade:0.4     自定义时长（秒）
#   留空 = 按 --xfade-type 决定；auto = 同一素材硬切、换素材叠化
#
# ⚠ 转场不许动时间轴。做法：转场落在**上一拍句末的 GAP 静音里**（终点正好是
#   下一句开口的时刻），入场那一拍多渲 x 秒、起始秒回拉 x 秒。于是
#   ① 全片总长仍等于 Σ拍长  ② 每句开口的那一帧和硬切版一模一样  ③ 不用做音频交叉淡化。
#   所以 x 默认 0.22 ≤ GAP 0.25；调大到盖住话尾会警告。
#   推导和逐步验证见 skills/ffmpeg-cookbook/ §转场。
#
# 产物: <project>/work/vNN.mp4 · work/video.mp4 · work/voice.m4a · <out>
set -euo pipefail

HERE_LIB="$(cd "$(dirname "$0")" && pwd)"
PROJECT=""; SHOTS="shots.tsv"; OUT=""; GAP=0.25; GAIN="4dB"
W=1080; H=1920; FPS=30; CRF=19; MAXUP=1.6
XFADE=0.22; XTYPE="auto"
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
    --xfade)      XFADE="$2"; shift 2;;    # 默认转场时长（秒）；0 = 全片硬切
    --xfade-type) XTYPE="$2"; shift 2;;    # 默认转场类型；auto = 同源硬切/换源叠化
    --no-xfade)   XFADE=0;    shift 1;;
    -h|--help) sed -n '2,40p' "$0"; exit 0;;
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

# ---- 把拍长对齐到整帧，且**按绝对边界**对齐 ----
# 每一拍单独编码时，ffmpeg 的 -t 会把时长向上取整到整帧（2.375s → 72 帧 = 2.400s）。
# 一拍多零点零几秒，concat 起来就**逐拍累加**：真实交付的 8 拍片子量出来，
# 最后一拍画面比它的配音晚了 171ms —— 一路越来越晚，而且没有任何报错。
#
# 修法：先算每一拍的**绝对**边界 T_k，各自取整到帧，再回推每拍占几帧。
# 这样误差不累积（每个边界各自只差半帧以内），而且音轨用同一套拍长，
# 音画从头到尾严丝合缝。
declare -a BT=()
BTS="$(/usr/bin/env python3 -c '
import sys
fps = float(sys.argv[1]); ts = [float(x) for x in sys.argv[2:]]
cum = 0.0; prev_f = 0; out = []; worst = 0.0; naive = 0.0
for t in ts:
    cum += t
    f = round(cum * fps)
    out.append((f - prev_f) / fps)
    prev_f = f
    naive += -(-t * fps // 1) / fps          # 老口径：逐拍向上取整
    worst = max(worst, abs(naive - cum))
print(" ".join(f"{x:.6f}" for x in out))
print(f"{worst*1000:.0f}")
' "$FPS" "${TS[@]}")"
BTLINE="$(printf '%s\n' "$BTS" | sed -n 1p)"
DRIFT="$(printf '%s\n' "$BTS" | sed -n 2p)"
for v in $BTLINE; do BT+=("$v"); done
[ "${#BT[@]}" = "${#TS[@]}" ] || { echo "  ✗ 拍长取整算错了" >&2; exit 5; }
if awk -v d="${DRIFT:-0}" 'BEGIN{ exit !(d>=20) }'; then
  echo "  · 拍长按绝对边界对齐到整帧（不这么做，末拍画面会比配音晚 ${DRIFT}ms，且逐拍累加）"
fi

# ---- 读 shots.tsv ----
declare -a KIND=() SRC=() SS=() EXTRA=() TSPEC=()
for name in "${CLIPS[@]}"; do
  line="$(awk -F'\t' -v n="$name" '$1==n{print; exit}' "$SHOTS")"
  [ -n "$line" ] || { echo "  ✗ shots.tsv 里没有 $name" >&2; exit 4; }
  k="$(printf '%s' "$line" | cut -f2)"
  s="$(printf '%s' "$line" | cut -f3)"
  t="$(printf '%s' "$line" | cut -f4)"; [ -n "$t" ] || t=0
  x="$(printf '%s' "$line" | cut -f5)"
  tr7="$(printf '%s' "$line" | cut -f7)"          # 第6列是给人看的画面说明，跳过
  case "$s" in /*) ;; *) s="$PROJECT/$s";; esac
  [ -f "$s" ] || { echo "  ✗ 素材不存在: $s ($name)" >&2; exit 4; }
  KIND+=("$k"); SRC+=("$s"); SS+=("$t"); EXTRA+=("$x"); TSPEC+=("$tr7")
done

# ---- 定每一拍的「入场转场」 ----
# XIN[i]=时长（0 表示硬切）  XT[i]=类型。第 0 拍永远没有入场转场。
echo "[1.5/5] 排转场（默认 ${XFADE}s / ${XTYPE}；转场落在上一拍的 GAP 静音里，不动时间轴）"
awk -v x="$XFADE" -v g="$GAP" 'BEGIN{ exit !(x>g+0.001) }' \
  && echo "  ⚠ 转场 ${XFADE}s 超过 GAP ${GAP}s —— 会盖住上一句的话尾，通常不想要" >&2
declare -a XIN=() XT=()
n=0
for name in "${CLIPS[@]}"; do
  if [ "$n" = 0 ]; then XIN+=(0); XT+=(cut); n=1; continue; fi
  spec="${TSPEC[$n]}"; tname=""; tdur=""
  if [ -n "$spec" ]; then
    tname="${spec%%:*}"
    case "$spec" in *:*) tdur="${spec#*:}";; esac
  elif [ "$XTYPE" = auto ]; then
    # 同一素材文件里前后两拍做叠化只会糊成一团（两帧都是同一个画面的近亲）。
    # 换素材才是观众感觉得到「换了一场」的地方，那里才需要转场。
    if [ "${SRC[$n]}" = "${SRC[$((n-1))]}" ]; then tname=cut; else tname=fade; fi
  else
    tname="$XTYPE"
  fi
  [ -n "$tdur" ] || tdur="$XFADE"
  case "$tname" in
    cut|none|hard|-) tdur=0; tname=cut;;
  esac
  awk -v d="$tdur" 'BEGIN{ exit !(d>0) }' || { tdur=0; tname=cut; }
  # 转场时长取整到帧。不取整的话它同时是「起始秒回拉多少」，0.22s @30fps = 6.6 帧，
  # 源就被采样在两帧之间，同一时刻两版取到的画面差半帧 —— 明明该一模一样的。
  if [ "$tname" != cut ]; then
    tdur="$(awk -v d="$tdur" -v f="$FPS" 'BEGIN{ n=int(d*f+0.5); if (n<1) n=1; printf "%.4f", n/f }')"
  fi
  # 转场不能长过前一拍（offset 会变负）
  awk -v d="$tdur" -v p="${BT[$((n-1))]}" 'BEGIN{ exit !(d>=p) }' \
    && { echo "  ⚠ ${name} 的入场转场 ${tdur}s 不短于上一拍 ${BT[$((n-1))]}s，改成硬切" >&2; tdur=0; tname=cut; }
  XIN+=("$tdur"); XT+=("$tname")
  if [ "$tname" = cut ]; then printf "  %s  ← 硬切\n" "$name"
  else printf "  %s  ← %s %.3fs\n" "$name" "$tname" "$tdur"; fi
  n=$((n+1))
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
  # 入场转场会吃掉这一拍开头的 x 秒，所以这一拍要多出 x 秒来喂它。多出来的 x 秒
  # 必须加在**前面**，不能让内容整体提前 —— 不然「这句开口那一帧」就和硬切版不是
  # 同一个画面了，开关转场会悄悄改变观众在关键时刻看到的东西。两种加法：
  #   起始秒还有余量 → 回拉 pull 秒，多播一点前面的内容（录屏、切片都走这条）
  #   起始秒是 0     → 冻结首帧顶 hp 秒（卡片走这条：动画不能在叠化过程中就开演）
  # pull + hp = x 恒成立，于是这一拍在绝对时间 T_k 上的画面和硬切版严格一致。
  xin="${XIN[$i]}"
  pull="$(awk -v s="${SS[$i]}" -v x="$xin" 'BEGIN{ printf "%.3f", (s<x)?s:x }')"
  hp="$(awk   -v x="$xin" -v p="$pull"    'BEGIN{ printf "%.3f", x-p }')"
  sse="$(awk  -v s="${SS[$i]}" -v p="$pull" 'BEGIN{ printf "%.3f", s-p }')"
  ctgt="$(fadd "${BT[$i]}" "$pull")"      # 编码器实际要渲的内容长度
  tgt="$(fadd "${BT[$i]}" "$xin")"        # 这一拍最终长度
  # 传给 ffmpeg 的 -t 减半帧：-t 收的是「PTS < t」的帧，而拍长打印成 %.3f 时可能
  # 微微进位（74 帧 = 2.466667s → "2.467"），刚好把第 75 帧也收进来，凭空多一帧。
  ctgt_enc="$(awk -v t="$ctgt" -v f="$FPS" 'BEGIN{printf "%.4f", t-0.5/f}')"
  case "${KIND[$i]}" in
    card)  enc_card  "${SRC[$i]}" "$ctgt_enc" "$o";;
    full)  enc_full  "${SRC[$i]}" "$ctgt_enc" "$o" "$sse";;
    fit)   enc_fit   "${SRC[$i]}" "$ctgt_enc" "$o" "$sse";;
    motion) enc_motion "${SRC[$i]}" "$ctgt_enc" "$o" "$sse" "${EXTRA[$i]} --lead ${pull}";;
    celeb) enc_celeb "${SRC[$i]}" "$ctgt_enc" "$o" "$sse";;
    patch) enc_patch "${SRC[$i]}" "$ctgt_enc" "$o" "$sse" "${EXTRA[$i]}";;
    *) echo "  ✗ 未知编码器 '${KIND[$i]}' ($name)" >&2; exit 4;;
  esac
  if awk -v v="$hp" 'BEGIN{ exit !(v>0.001) }'; then
    "$FF" -nostdin -y -v error -i "$o" \
      -vf "tpad=start_mode=clone:start_duration=${hp},setpts=PTS-STARTPTS,$V" \
      -an -c:v libx264 -crf "$CRF" -pix_fmt yuv420p "$o.hp.mp4"
    mv "$o.hp.mp4" "$o"
  fi
  got="$(dur "$o")"
  # 素材不够长 → 冻结末帧补足。两个理由，缺一不可：
  #   ① 拼出来的视频比音轨短，mux 的 -shortest 会把最后几句配音直接切掉，还不报错
  #      （真交付过一条尾巴被吃掉 4.2s 的片）
  #   ② 哪怕只短一帧，后面每一拍都跟着提前一帧，而且**逐拍累加** ——
  #      所以门槛是半帧，不是「差不多就行」。卡片素材经常正好短一帧。
  # 短得多就是真缺陷，照样喊出来；只短一两帧是取帧余数，补掉即可，不用吵。
  if awk -v a="$got" -v b="$tgt" -v f="$FPS" 'BEGIN{ exit !((b-a) > 0.5/f) }'; then
    pad="$(awk -v a="$got" -v b="$tgt" 'BEGIN{printf "%.3f", b-a}')"
    "$FF" -nostdin -y -v error -i "$o" -vf "tpad=stop_mode=clone:stop_duration=${pad},$V" \
      -an -c:v libx264 -crf "$CRF" -pix_fmt yuv420p "$o.pad.mp4"
    mv "$o.pad.mp4" "$o"
    got="$(dur "$o")"
    awk -v p="$pad" 'BEGIN{ exit !(p > 0.20) }' \
      && echo "  ⚠ $name 素材只够 ${tgt}s 里的一部分，已冻结末帧补 ${pad}s —— 画面会定住，去换更长的素材" >&2
  fi
  awk -v a="$got" -v b="$tgt" 'BEGIN{ if ((a-b)>0.15) exit 1 }' \
    || echo "  ⚠ $name 实际 ${got}s ＞ 目标 ${tgt}s" >&2
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

# ---- 拼接 ----
# 全片硬切走 concat demuxer（快、无重编码风险）；有转场就走 filter_complex。
NX=0
for v in "${XIN[@]}"; do awk -v d="$v" 'BEGIN{ exit !(d>0) }' && NX=$((NX+1)); done

if [ "$NX" = 0 ]; then
  echo "[3/5] concat 视频（全片硬切）"
  "$FF" -nostdin -y -v error -f concat -safe 0 -i "$WORK/vl.txt" \
    -c:v libx264 -crf "$CRF" -pix_fmt yuv420p "$WORK/video.mp4"
else
  echo "[3/5] 拼接视频（${NX} 处转场 / $(( ${#CLIPS[@]} - 1 - NX )) 处硬切）"
  # 时间轴推导（每一步都用**绝对**时间锚定，所以误差不累积）：
  #   T_k = 前 k 拍的拍长之和；进入第 k+1 拍的转场时长 x_k
  #   offset_k = T_k − x_k       转场结束的那一刻正好是第 k+1 句开口
  #   L_{k+1}  = d_{k+1} + x_k   （上面编码时已经多渲了）
  #   拼完长度 = offset_k + L_{k+1} = T_k + d_{k+1} = T_{k+1}   ← 和硬切一模一样
  # settb 不能省：concat 出来是 1/1000000，xfade 要求两路时基一致，否则直接报错。
  VIN=(); FC=""; NC=${#CLIPS[@]}
  for ((k=0;k<NC;k++)); do
    VIN+=(-i "$(printf '%s/v%02d.mp4' "$WORK" $((k+1)))")
    FC+="[${k}:v]fps=${FPS},settb=1/${FPS},setpts=PTS-STARTPTS[s${k}];"
  done
  PREV="[s0]"; ACC=0
  for ((k=1;k<NC;k++)); do
    ACC="$(fadd "$ACC" "${BT[$((k-1))]}")"          # ← T_k
    if awk -v d="${XIN[$k]}" 'BEGIN{ exit !(d>0) }'; then
      off="$(awk -v t="$ACC" -v x="${XIN[$k]}" 'BEGIN{ v=t-x; if (v<0) v=0; printf "%.4f", v }')"
      FC+="${PREV}[s${k}]xfade=transition=${XT[$k]}:duration=${XIN[$k]}:offset=${off},settb=1/${FPS}[j${k}];"
    else
      FC+="${PREV}[s${k}]concat=n=2:v=1:a=0,settb=1/${FPS}[j${k}];"
    fi
    PREV="[j${k}]"
  done
  FC="${FC%;}"
  "$FF" -nostdin -y -v error "${VIN[@]}" -filter_complex "$FC" -map "$PREV" \
    -an -c:v libx264 -crf "$CRF" -pix_fmt yuv420p "$WORK/video.mp4"
fi
echo "  video $(dur "$WORK/video.mp4")s"

echo "[4/5] 拼音轨（每句 apad 到本拍时长，防漂移）"
ain=(); fc=""; n=0
for name in "${CLIPS[@]}"; do
  ain+=(-i "$PROJECT/audio/$name.mp3")
  fc+="[${n}:a]aresample=44100,volume=${GAIN},apad,atrim=0:${BT[$n]}[a${n}];"
  n=$((n+1))
done
for ((k=0;k<n;k++)); do fc+="[a${k}]"; done
fc+="concat=n=${n}:v=0:a=1[a]"
"$FF" -nostdin -y -v error "${ain[@]}" -filter_complex "$fc" -map "[a]" "$WORK/voice.m4a"
echo "  voice $(dur "$WORK/voice.m4a")s"

echo "[5/5] mux"
# -shortest 会以短的那一路为准。视频只要短哪怕半帧，末尾配音就被切掉，而且不报错 ——
# 交付过一条尾巴被吃掉 4.2s 的片就是这么来的。所以 mux 之前先量，短了就冻末帧顶上。
VD="$(dur "$WORK/video.mp4")"; AD="$(dur "$WORK/voice.m4a")"
MUXV="$WORK/video.mp4"
if awk -v v="$VD" -v a="$AD" 'BEGIN{ exit !((a-v) > 0.005) }'; then
  short="$(awk -v v="$VD" -v a="$AD" 'BEGIN{printf "%.3f", a-v}')"
  "$FF" -nostdin -y -v error -i "$WORK/video.mp4" \
    -vf "tpad=stop_mode=clone:stop_duration=$(awk -v s="$short" 'BEGIN{printf "%.3f", s+0.08}'),$V" \
    -an -c:v libx264 -crf "$CRF" -pix_fmt yuv420p "$WORK/video-padded.mp4"
  MUXV="$WORK/video-padded.mp4"
  if awk -v s="$short" 'BEGIN{ exit !(s > 0.30) }'; then
    echo "  ⚠ 视频比配音短 ${short}s，已冻结末帧补上 —— 这么大的缺口说明某拍素材不够，去查上面的逐拍报告" >&2
  else
    echo "  · 视频比配音短 ${short}s（取帧余数），冻末帧补齐，配音一秒不丢"
  fi
fi
"$FF" -nostdin -y -v error -i "$MUXV" -i "$WORK/voice.m4a" \
  -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart "$OUT"

echo "=== RESULT ==="
"$FP" -v error -show_entries format=duration:stream=width,height,codec_name \
  -of default=noprint_wrappers=1 "$OUT"
du -h "$OUT" | cut -f1
