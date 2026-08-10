#!/usr/bin/env bash
# setup.sh — 把宿主环境装成「能做视频」的样子，然后按**能力**（不是按工具）汇报。
#
# 用法:
#   ./setup.sh              # 装齐所有能装的
#   ./setup.sh --check      # 只体检不安装
#   ./setup.sh --minimal    # 只装核心（ffmpeg + Pillow），跳过 playwright / yt-dlp
#
# 为什么需要这个：skill 只是**知识和脚本**，不是能力。
# 一个空白 agent 拿到 skill 之后能不能真做视频，取决于它宿主机上有没有这些东西，
# 以及能不能出网。这个脚本把这件事说清楚，并尽量自动补齐。
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CHECK=0; MINIMAL=0
for a in "$@"; do
  case "$a" in --check) CHECK=1;; --minimal) MINIMAL=1;; esac
done

say(){ printf '\n\033[1m== %s\033[0m\n' "$1"; }
ok(){  printf '  ✓ %s\n' "$1"; }
no(){  printf '  ✗ %s\n' "$1"; }
opt(){ printf '  ○ %s\n' "$1"; }

PM=""
command -v brew    >/dev/null && PM=brew
[ -z "$PM" ] && command -v apt-get >/dev/null && PM=apt
[ -z "$PM" ] && command -v dnf     >/dev/null && PM=dnf
[ -z "$PM" ] && command -v apk     >/dev/null && PM=apk

install_pkg(){
  local pkg="$1"
  [ "$CHECK" = 1 ] && { opt "缺 $pkg（--check 模式不装）"; return 1; }
  case "$PM" in
    brew) brew install "$pkg" >/dev/null 2>&1;;
    apt)  sudo apt-get update -qq >/dev/null 2>&1 && sudo apt-get install -y -qq "$pkg" >/dev/null 2>&1;;
    dnf)  sudo dnf install -y -q "$pkg" >/dev/null 2>&1;;
    apk)  sudo apk add --no-cache "$pkg" >/dev/null 2>&1;;
    *) return 1;;
  esac
}

say "宿主环境"
printf '  OS: %s  包管理器: %s\n' "$(uname -s)" "${PM:-无（要手动装依赖）}"
command -v python3 >/dev/null && printf '  python3: %s\n' "$(python3 -V 2>&1)"
command -v node    >/dev/null && printf '  node:    %s\n' "$(node -v)"

# ---------------------------------------------------------------- 核心
say "核心（缺了什么都做不了）"
if ! command -v ffmpeg >/dev/null; then install_pkg ffmpeg; fi
if command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null; then
  ok "ffmpeg $(ffmpeg -version 2>/dev/null | head -1 | awk '{print $3}')"
  ffmpeg -v error -encoders 2>/dev/null | grep -q libx264 && ok "libx264" || no "没有 libx264 —— 出不了 H.264"
  ffmpeg -v error -filters 2>/dev/null | grep -qE '^ .. (ass|subtitles) ' \
    && ok "libass（ASS 字幕可用）" || opt "无 libass —— 字幕走 PIL overlay 路线，这是预期内的"
else no "ffmpeg 缺失，且自动安装失败 —— 手动装：https://ffmpeg.org/download.html"; fi

PY=""
for c in /usr/bin/python3 python3; do
  command -v "$c" >/dev/null && "$c" -c "import PIL" 2>/dev/null && { PY="$c"; break; }
done
if [ -z "$PY" ] && [ "$CHECK" = 0 ] && command -v python3 >/dev/null; then
  python3 -m pip install --quiet --user Pillow >/dev/null 2>&1
  python3 -c "import PIL" 2>/dev/null && PY=python3
fi
[ -n "$PY" ] && ok "python3 + Pillow ($PY)" || no "python3 + Pillow 缺失 —— 字幕/封面/图片补丁都不能用"

# ---------------------------------------------------------------- 可选
if [ "$MINIMAL" = 0 ]; then
  say "可选（对应具体能力）"
  if command -v node >/dev/null; then
    ok "node $(node -v)"
    if ! node -e "require('playwright')" 2>/dev/null; then
      [ "$CHECK" = 0 ] && (cd "$ROOT" && npm install --silent playwright >/dev/null 2>&1)
    fi
    if node -e "require('playwright')" 2>/dev/null; then
      ok "playwright"
      if [ "$CHECK" = 0 ]; then
        npx --yes playwright install chromium >/dev/null 2>&1 \
          && ok "chromium 已就绪" || opt "chromium 没装上（可能是出网受限）—— 录屏/渲卡不可用"
      fi
    else opt "playwright 没装上 —— 产品录屏 / HTML 卡渲染不可用"; fi
  else opt "node 缺失 —— 配音脚本、录屏、渲卡都不可用"; fi

  command -v yt-dlp >/dev/null || install_pkg yt-dlp
  command -v yt-dlp >/dev/null && ok "yt-dlp" || opt "yt-dlp 缺失 —— 扒外部真实切片不可用"
fi

# ---------------------------------------------------------------- 出网
say "出网（沙箱里最容易卡的地方）"
probe(){ curl -s -o /dev/null -m 8 -w '%{http_code}' "$1" 2>/dev/null; }
c=$(probe https://api.minimax.io/); [ "${c:-000}" != "000" ] && ok "api.minimax.io 可达（配音）" || opt "api.minimax.io 不可达 —— 配音不可用，先用占位配音"
c=$(probe https://www.youtube.com/); [ "${c:-000}" != "000" ] && ok "youtube 可达（扒素材）" || opt "youtube 不可达 —— 换国内源或改用自有素材"

# ---------------------------------------------------------------- 能力汇总
say "能力汇总（这才是你关心的）"
cap(){ if eval "$2"; then ok "$1"; else no "$1 —— $3"; fi }
cap "剪辑合成（build / 竖版化 / 交付）" 'command -v ffmpeg >/dev/null && command -v ffprobe >/dev/null' "装 ffmpeg"
cap "字幕 / 封面 / 图片补丁"           '[ -n "'"$PY"'" ]' "装 python3 + Pillow"
cap "占位配音（无需任何 key）"          'command -v ffmpeg >/dev/null' "装 ffmpeg"
cap "真配音（MiniMax）"                'command -v node >/dev/null && [ -n "${MINIMAX_API_KEY:-}" ]' "装 node + 设 MINIMAX_API_KEY（见 SECRETS-CHECKLIST.md）"
cap "产品录屏"                          'node -e "require(\"playwright\")" 2>/dev/null' "npm i playwright && npx playwright install chromium，另需目标站凭据"
cap "HTML 卡渲染"                       'node -e "require(\"playwright\")" 2>/dev/null' "同上"
cap "扒外部真实切片"                    'command -v yt-dlp >/dev/null' "装 yt-dlp"

say "下一步"
echo "  ./tests/check-deps.sh              # 更细的依赖体检"
echo "  cat skills/video-master/SKILL.md   # 总纲"
echo "  lib/init-project.sh <工程目录>      # 建工程，它会打印后续每一步的完整命令"
echo
echo "  只有「剪辑合成 + 字幕 + 占位配音」三项就已经能跑通全流程出一版粗剪了，"
echo "  录屏 / 真配音 / 扒素材缺哪个补哪个。"
