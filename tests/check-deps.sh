#!/usr/bin/env bash
# check-deps.sh — 开工前查工具链。缺什么、缺了会卡在哪一步，一次说清。
set -uo pipefail
fail=0; warn=0
ok(){   printf '  ✓ %s\n' "$1"; }
bad(){  printf '  ✗ %s\n' "$1"; fail=1; }
opt(){  printf '  ○ %s\n' "$1"; warn=1; }

echo "== 必须"
command -v ffmpeg  >/dev/null && ok "ffmpeg  $(ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}')" || bad "ffmpeg 缺失 —— 整条管线不可用"
command -v ffprobe >/dev/null && ok "ffprobe" || bad "ffprobe 缺失 —— 时间轴全靠它量，不可用"

PY=""
for cand in /usr/bin/python3 python3; do
  if command -v "$cand" >/dev/null && "$cand" -c "import PIL" 2>/dev/null; then PY="$cand"; break; fi
done
if [ -n "$PY" ]; then ok "python3 + Pillow ($PY)"; else
  if command -v python3 >/dev/null; then bad "python3 有但没 Pillow —— 字幕/封面/图片补丁不可用。macOS 试 /usr/bin/python3，或 pip install Pillow"
  else bad "python3 缺失 —— 字幕/封面不可用"; fi
fi

echo "== ffmpeg 能力"
if ffmpeg -v error -encoders 2>/dev/null | grep -q libx264; then ok "libx264"; else bad "没有 libx264 —— 没法出 H.264"; fi
if ffmpeg -v error -encoders 2>/dev/null | grep -qE '^ A.*\baac\b'; then ok "aac 编码器"; else bad "没有 aac 编码器 —— 没法 mux 音轨"; fi
if ffmpeg -v error -encoders 2>/dev/null | grep -q libmp3lame; then ok "libmp3lame"; else opt "没有 libmp3lame —— examples 的假配音生成不了（真配音是 TTS 下发的 mp3，不受影响）"; fi
if ffmpeg -v error -filters 2>/dev/null | grep -qE '^ .. (ass|subtitles) '; then
  ok "libass（可以用 ASS 烧字幕）"
else
  opt "无 libass —— 字幕必须走 PIL overlay 路线（lib/gen-subs.py + lib/burn-subs.sh），这是预期内的"
fi

echo "== 按需"
command -v node   >/dev/null && ok "node $(node -v)" || opt "node 缺失 —— 配音 (lib/gen-voice.mjs) / 录屏 (playwright) 不可用"
command -v yt-dlp >/dev/null && ok "yt-dlp" || opt "yt-dlp 缺失 —— 扒真实切片素材不可用"
if command -v node >/dev/null && node -e "require('playwright')" 2>/dev/null; then ok "playwright"; else opt "playwright 缺失 —— 产品录屏不可用（npm i playwright && npx playwright install chromium）"; fi

echo "== 字体"
F="/System/Library/Fonts/STHeiti Medium.ttc"
[ -f "$F" ] && ok "中文字体 STHeiti Medium" || opt "找不到 $F —— 字幕/封面要用 --font 指定别的中文字体"

echo
[ "$fail" = 0 ] && echo "必须项齐全$( [ "$warn" = 1 ] && echo "（有可选项缺失，见上面 ○）" )" || echo "有必须项缺失，先补齐"
exit "$fail"
