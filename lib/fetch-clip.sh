#!/usr/bin/env bash
# fetch-clip.sh — 扒真实视频切片素材（yt-dlp 封装）+ 落地后立刻体检。
#
#   fetch-clip.sh search "<关键词>" [-n 8] [--site youtube|bilibili]
#        搜候选，只打印 id / 时长 / 分辨率 / 标题，不下载。先看再下。
#
#   fetch-clip.sh get <url> -o footage/ext/<name>.mp4 [--site ...] [--codec h264|any] [--max-h 1080]
#        下载 + 自动体检。默认强制 h264（AV1/HEVC 在部分 ffmpeg 构建上解不了）。
#
#   fetch-clip.sh probe <file> [--grid 3x3] [--need <秒>]
#        体检：画幅 / 编码 / 时长 / 转竖版要放大几倍 + 抽帧拼一张контакт图给人眼看水印。
#
# 为什么每次都要体检:
#   · 免费 stock 素材常带巨大浮水印（"SLOW VIDEO" / "CLICK TO DOWNLOAD" / "STOCK"），
#     ffprobe 看不出来，只能抽帧看。本 repo 参考库里就有一条 1280×720 的钞票素材带
#     满屏 "STOCK" 字样 —— 不抽帧就会剪进片子里。
#   · 分辨率决定转竖版后糊不糊（见 skills/real-clip-mashup/ 的放大倍数阶梯）。
set -euo pipefail

FF=${FF:-ffmpeg}; FP=${FP:-ffprobe}
CMD="${1:-}"; shift 2>/dev/null || true
[ -n "$CMD" ] || { sed -n '2,20p' "$0"; exit 2; }

need_ytdlp(){ command -v yt-dlp >/dev/null || { echo "缺 yt-dlp（brew install yt-dlp）" >&2; exit 3; }; }

# 站点预设：某些站直连返回 412/403，要带 UA + Referer
site_args(){
  case "${1:-}" in
    bilibili) printf '%s\0' --user-agent "Mozilla/5.0" --add-header "Referer:https://www.bilibili.com/";;
    douyin)   printf '%s\0' --user-agent "Mozilla/5.0" --add-header "Referer:https://www.douyin.com/";;
    *) : ;;
  esac
}

do_probe(){
  local f="$1" grid="${2:-3x3}" need="${3:-}"
  [ -f "$f" ] || { echo "文件不存在: $f" >&2; return 2; }
  local w h codec dur
  IFS=',' read -r codec w h < <("$FP" -v error -select_streams v:0 \
      -show_entries stream=codec_name,width,height -of csv=p=0 "$f")
  dur=$("$FP" -v error -show_entries format=duration -of csv=p=0 "$f")
  local ar up
  ar=$(awk -v w="$w" -v h="$h" 'BEGIN{printf "%.2f", w/h}')
  up=$(awk -v w="$w" 'BEGIN{printf "%.2f", 1080/w}')   # blur 模式前景铺满 1080 宽要放大几倍
  printf '  %s\n' "$f"
  printf '    %sx%s  AR %s  %s  %.1fs\n' "$w" "$h" "$ar" "$codec" "$dur"
  printf '    转竖版前景放大 %s×  ' "$up"
  awk -v u="$up" 'BEGIN{ if(u<=1.0) print "（降采样，最锐）";
                         else if(u<=1.8) print "（可用，会加 unsharp）";
                         else if(u<=2.5) print "（勉强，优先换源）";
                         else print "（太糊，别用）" }'
  case "$codec" in
    av1|hevc) echo "    ! 编码是 $codec —— 部分 ffmpeg 构建解不了，重下时加 --codec h264";;
  esac
  if [ -n "$need" ]; then
    awk -v d="$dur" -v n="$need" 'BEGIN{exit !(d>=n)}' \
      || echo "    ✗ 只有 ${dur}s，短于需要的 ${need}s —— 换素材或 setpts 放慢"
  fi
  # 抽帧拼图：给人眼看水印 / 构图 / 挑起始点
  local cols rows n step sheet
  cols="${grid%x*}"; rows="${grid#*x}"; n=$((cols*rows))
  step=$(awk -v d="$dur" -v n="$n" 'BEGIN{s=int(d*30/n); if(s<1)s=1; print s}')
  sheet="${f%.*}-contact.jpg"
  "$FF" -nostdin -y -v error -i "$f" \
     -vf "select='not(mod(n,${step}))',scale=320:-2,tile=${grid}" -frames:v 1 -q:v 3 "$sheet" 2>/dev/null \
     && printf '    抽帧图 → %s  （必须打开看一眼：有没有水印、构图能不能用、从第几秒切）\n' "$sheet" \
     || echo "    ⚠ 抽帧失败"
}

case "$CMD" in
  search)
    need_ytdlp
    Q="${1:-}"; shift 2>/dev/null || true
    [ -n "$Q" ] || { echo '用法: fetch-clip.sh search "<关键词>" [-n 8]' >&2; exit 2; }
    N=8; SITE=youtube
    while [ $# -gt 0 ]; do
      case "$1" in -n) N="$2"; shift 2;; --site) SITE="$2"; shift 2;; *) shift;; esac
    done
    echo "搜 ${SITE}: ${Q}  (前 ${N} 条)"
    echo "id            时长   分辨率      标题"
    yt-dlp "ytsearch${N}:${Q}" --no-warnings --flat-playlist \
      --print "%(id)-12s %(duration)5.5s %(resolution)-11s %(title).60s" 2>/dev/null \
      || { echo "搜索失败（网络 / yt-dlp 版本）" >&2; exit 4; }
    echo
    echo "挑好之后: fetch-clip.sh get <id或url> -o footage/ext/<名字>.mp4"
    ;;

  get)
    need_ytdlp
    URL="${1:-}"; shift 2>/dev/null || true
    OUT=""; SITE=""; CODEC=h264; MAXH=1080
    while [ $# -gt 0 ]; do
      case "$1" in
        -o|--out) OUT="$2"; shift 2;;
        --site) SITE="$2"; shift 2;;
        --codec) CODEC="$2"; shift 2;;
        --max-h) MAXH="$2"; shift 2;;
        *) shift;;
      esac
    done
    [ -n "$URL" ] && [ -n "$OUT" ] || { echo '用法: fetch-clip.sh get <url> -o <path.mp4>' >&2; exit 2; }
    mkdir -p "$(dirname "$OUT")"
    args=(-o "$OUT" --no-warnings --merge-output-format mp4)
    [ "$CODEC" = h264 ] && args+=(-S "vcodec:h264,res:${MAXH}") || args+=(-S "res:${MAXH}")
    if [ -n "$SITE" ]; then
      while IFS= read -r -d '' a; do args+=("$a"); done < <(site_args "$SITE")
    fi
    echo "下载 → $OUT"
    yt-dlp "${args[@]}" "$URL" || {
      echo "✗ 下载失败。常见原因：" >&2
      echo "  · 412/403 → 加 --site bilibili / --site douyin（带 UA + Referer）" >&2
      echo "  · 需要登录 → 换公开源" >&2
      echo "  · 格式不可用 → 试 --codec any" >&2
      exit 5; }
    echo "体检:"
    do_probe "$OUT" 3x3
    ;;

  probe)
    F="${1:-}"; shift 2>/dev/null || true
    GRID=3x3; NEED=""
    while [ $# -gt 0 ]; do
      case "$1" in --grid) GRID="$2"; shift 2;; --need) NEED="$2"; shift 2;; *) shift;; esac
    done
    [ -n "$F" ] || { echo '用法: fetch-clip.sh probe <file> [--grid 3x3] [--need 6]' >&2; exit 2; }
    do_probe "$F" "$GRID" "$NEED"
    ;;

  *) echo "未知子命令: $CMD" >&2; sed -n '2,20p' "$0"; exit 2;;
esac
