#!/usr/bin/env bash
# make-placeholders.sh — 给任意工程造占位配音（和可选的占位素材），
# 让你在**还没有 API key / 还没找到素材**的时候就先把整条管线跑通。
#
# 用法:
#   make-placeholders.sh <project> [--rate 6.35] [--footage] [--force]
#
#   --footage   连占位素材一起造；并把 shots.tsv 里指向不存在文件的行改到占位素材、
#               补齐 clips.json 里有但 shots.tsv 缺的拍
#   --force     覆盖已有的 audio/*.mp3（默认跳过已存在的，免得盖掉真配音）
#
# 产物:
#   audio/cNN.mp3                      正弦占位音，时长 = 该句字数 ÷ rate（默认实测 6.35 字/秒）
#   audio/.placeholder                 标记文件 —— 提醒你这些不是真配音
#   --footage 时另有:
#     footage/ext/placeholder-horiz.mp4  1920×1080 横屏（喂 celeb）
#     footage/rec/placeholder-vert.mp4   720×1280 竖版（喂 full）
#     html/beats/placeholder-card.mp4    1080×1920 卡（喂 card）
#
# 为什么值得先跑占位:
#   · 没 key 的 agent 也能验证「时间轴 / 分镜覆盖 / 字幕条数 / 画面构成」全对，
#     再去花 TTS 额度。
#   · 占位音时长按真实语速算，所以粗剪出来的节奏跟成片接近。
#
# 🔴 占位配音**绝不能交付**。verify-audio / audit 都会照常通过（它们只看时长和响度），
#    所以自己盯着 audio/.placeholder 这个标记，换成真配音后删掉它。
set -euo pipefail
FF=${FF:-ffmpeg}
PROJECT="${1:-}"; shift 2>/dev/null || true
[ -n "$PROJECT" ] && [ -d "$PROJECT" ] || { sed -n '2,12p' "$0"; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd)"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "$PROJECT/clips.json" ] || { echo "缺 $PROJECT/clips.json" >&2; exit 2; }

RATE=6.35; FOOTAGE=0; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --rate) RATE="$2"; shift 2;;
    --footage) FOOTAGE=1; shift;;
    --force) FORCE=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

mkdir -p "$PROJECT/audio"
echo "[占位配音] rate=${RATE} 字/秒"
n=0
while IFS=$'\t' read -r name secs; do
  [ -n "$name" ] || continue
  out="$PROJECT/audio/$name.mp3"
  if [ -s "$out" ] && [ "$FORCE" = 0 ]; then printf '  [skip] %s（已存在）\n' "$name"; continue; fi
  # 每句换个频率，粗剪时能听出切换点
  f=$(( 220 + n * 37 % 160 ))
  "$FF" -nostdin -y -v error -f lavfi -i "sine=frequency=${f}:duration=${secs}" \
        -c:a libmp3lame -b:a 128k "$out"
  printf '  %s  %ss\n' "$name" "$secs"
  n=$((n+1))
done < <(/usr/bin/env python3 -c '
import json,sys
rate=float(sys.argv[2])
for c in json.load(open(sys.argv[1], encoding="utf-8")):
    print(c["name"] + "\t" + str(max(1.2, round(len(c.get("text","")) / rate, 2))))
' "$PROJECT/clips.json" "$RATE")

cat > "$PROJECT/audio/.placeholder" <<EOF
这些是 make-placeholders.sh 造的**占位正弦音**，不是真配音。
时长按 ${RATE} 字/秒 估算，用来先跑通管线。
换成真配音（lib/gen-voice.mjs）之后删掉本文件。
EOF
echo "  → 标记 audio/.placeholder（换成真配音后删掉）"

if [ "$FOOTAGE" = 1 ]; then
  echo "[占位素材]"
  mkdir -p "$PROJECT/footage/ext" "$PROJECT/footage/rec" "$PROJECT/html/beats"
  "$FF" -nostdin -y -v error -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=60" \
        -c:v libx264 -crf 26 -pix_fmt yuv420p "$PROJECT/footage/ext/placeholder-horiz.mp4"
  "$FF" -nostdin -y -v error -f lavfi -i "smptebars=size=720x1280:rate=30:duration=60" \
        -c:v libx264 -crf 26 -pix_fmt yuv420p "$PROJECT/footage/rec/placeholder-vert.mp4"
  "$FF" -nostdin -y -v error \
        -f lavfi -i "gradients=size=1080x1920:rate=30:duration=60:c0=0x1a1230:c1=0x0a0a12" \
        -c:v libx264 -crf 26 -pix_fmt yuv420p "$PROJECT/html/beats/placeholder-card.mp4"
  echo "  footage/ext/placeholder-horiz.mp4  footage/rec/placeholder-vert.mp4  html/beats/placeholder-card.mp4"

  # shots.tsv：① 指向不存在文件的行改到占位素材 ② 补齐 clips.json 里有但这儿缺的拍。
  #   绝不动已经指向真素材的行。缺行不补的话 build 会在第一个缺的拍上直接失败。
  /usr/bin/env python3 "$REPO/lib/_fix_shots.py" "$PROJECT"
fi

echo
echo "下一步（占位也能一路跑到底，先把节奏和构成看对）:"
echo "  ${REPO}/lib/build-vertical.sh --project ${PROJECT} --out draft-nosub.mp4"
echo "  /usr/bin/python3 ${REPO}/lib/gen-subs.py --project ${PROJECT}"
echo "  ${REPO}/lib/burn-subs.sh draft-nosub.mp4 draft-v1.mp4 --manifest ${PROJECT}/subs/manifest.tsv"
echo "  ${REPO}/lib/audit-video.sh --project ${PROJECT} --video draft-v1.mp4"
echo
echo "🔴 占位配音绝不能交付。拿到 key 后用 lib/gen-voice.mjs 覆盖，再删掉 audio/.placeholder。"
