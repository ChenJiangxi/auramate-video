#!/usr/bin/env bash
# make-fixtures.sh — 造出跑通管线所需的假素材和假配音，**不需要任何 API key**。
# 目的：让零 context 的 agent 能先跑通一次完整管线，再换成真素材/真配音。
#
# 产物:
#   audio/cNN.mp3       正弦音，时长 = 文案字数 / 5（模拟 1.28 倍速中文口播）
#   footage/clip-horiz.mp4   1920×1080 横屏（喂 celeb 编码器）
#   footage/card-vert.mp4    1080×1920 竖版卡（喂 card 编码器）
#   footage/rec-vert.mp4     720×1280 竖版录屏（喂 full 编码器，故意低分辨率验证升采样锐化）
set -euo pipefail
FF=${FF:-ffmpeg}
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
mkdir -p audio footage

echo "[fixtures] 配音（正弦占位）"
python3 -c '
import json
for c in json.load(open("clips.json")):
    print(c["name"], max(1.2, round(len(c["text"])/5.0, 2)))
' | while read -r name d; do
  # 每句换个频率，方便听出切换点
  f=$(( 220 + RANDOM % 120 ))
  "$FF" -nostdin -y -v error -f lavfi -i "sine=frequency=${f}:duration=${d}" \
        -c:a libmp3lame -b:a 128k "audio/${name}.mp3"
  printf '  %s  %ss\n' "$name" "$d"
done

echo "[fixtures] 素材"
"$FF" -nostdin -y -v error -f lavfi -i "testsrc2=size=1920x1080:rate=30:duration=12" \
      -c:v libx264 -crf 22 -pix_fmt yuv420p footage/clip-horiz.mp4
"$FF" -nostdin -y -v error -f lavfi -i "gradients=size=1080x1920:rate=30:duration=12:c0=0x1a1230:c1=0x0a0a12" \
      -c:v libx264 -crf 22 -pix_fmt yuv420p footage/card-vert.mp4
"$FF" -nostdin -y -v error -f lavfi -i "smptebars=size=720x1280:rate=30:duration=12" \
      -c:v libx264 -crf 22 -pix_fmt yuv420p footage/rec-vert.mp4
echo "  ok: $(ls footage | tr '\n' ' ')"
