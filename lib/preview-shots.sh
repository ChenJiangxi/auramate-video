#!/usr/bin/env bash
# preview-shots.sh — 在正式合成之前，把「每句台词 ↔ 那一拍实际画面」摆在一起核对。
#
# 用法:
#   preview-shots.sh --project <dir> [--shots shots.tsv] [--gap 0.25] [--cols 4]
#
# 产出:
#   work/preview/<clip>.png    每拍的代表帧（按该拍**实际会用到的时间窗**中点抽）
#   work/preview/contact.jpg   全部拼成一张，打开就能逐拍看
#   终端打印「台词 ↔ 画面说明」对照表
#
# 为什么必须有这一步：
#   agent 看不见画面。按秒数猜框、按印象填 shots.tsv，出来就会「说 A 显 B」——
#   这是被打回最多的一类问题（`skills/video-master/` H4「说什么显什么」）。
#   写完 shots.tsv 先跑这个，看一眼再去合成，比出片后返工便宜得多。
#
# shots.tsv 建议加第 6 列写「这一拍画面是什么」，本脚本会把它和台词并排打出来；
# 没写会提示你补上 —— 逼你把映射关系写下来，而不是留在脑子里。
set -euo pipefail
FF=${FF:-ffmpeg}; FP=${FP:-ffprobe}

PROJECT=""; SHOTS="shots.tsv"; GAP=0.25; COLS=4
while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$2"; shift 2;;
    --shots) SHOTS="$2"; shift 2;;
    --gap) GAP="$2"; shift 2;;
    --cols) COLS="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -n "$PROJECT" ] && [ -d "$PROJECT" ] || { sed -n '2,12p' "$0"; exit 2; }
PROJECT="$(cd "$PROJECT" && pwd)"
case "$SHOTS" in /*) ;; *) SHOTS="$PROJECT/$SHOTS";; esac
[ -f "$SHOTS" ] || { echo "找不到 $SHOTS" >&2; exit 2; }
[ -f "$PROJECT/clips.json" ] || { echo "找不到 clips.json" >&2; exit 2; }

OUT="$PROJECT/work/preview"; rm -rf "$OUT"; mkdir -p "$OUT"
missing_note=0; n=0

printf '\n%-5s %-34s %s\n' "拍" "台词" "画面（第6列说明）"
printf '%s\n' "--------------------------------------------------------------------------------"

while IFS=$'\t' read -r clip text; do
  [ -n "$clip" ] || continue
  line="$(awk -F'\t' -v c="$clip" '$1==c{print; exit}' "$SHOTS")"
  if [ -z "$line" ]; then
    printf '%-5s %-34s %s\n' "$clip" "${text:0:16}" "✗ shots.tsv 里没有这一拍"
    continue
  fi
  kind="$(printf '%s' "$line" | cut -f2)"
  src="$(printf '%s' "$line" | cut -f3)"
  ss="$(printf '%s' "$line" | cut -f4)"; [ -n "$ss" ] || ss=0
  note="$(printf '%s' "$line" | cut -f6)"
  case "$src" in /*) ;; *) src="$PROJECT/$src";; esac

  # 这一拍多长：有配音就按配音，没有就按 3.5s 兜底
  a="$PROJECT/audio/$clip.mp3"
  if [ -s "$a" ]; then
    d="$("$FP" -v error -show_entries format=duration -of csv=p=0 "$a")"
    beat="$(awk -v x="$d" -v g="$GAP" 'BEGIN{printf "%.2f", x+g}')"
  else beat=3.5; fi
  mid="$(awk -v s="$ss" -v b="$beat" 'BEGIN{printf "%.2f", s+b/2}')"

  if [ -f "$src" ]; then
    "$FF" -nostdin -y -v error -ss "$mid" -i "$src" -frames:v 1 \
      -vf "scale=220:-2,drawtext=text='${clip}':x=8:y=8:fontsize=22:fontcolor=yellow:box=1:boxcolor=black@0.6:boxborderw=6" \
      "$OUT/$clip.png" 2>/dev/null \
      || "$FF" -nostdin -y -v error -ss "$mid" -i "$src" -frames:v 1 -vf "scale=220:-2" "$OUT/$clip.png"
    n=$((n+1))
  else
    printf '%-5s %-34s %s\n' "$clip" "${text:0:16}" "✗ 素材不存在: $src"
    continue
  fi

  if [ -z "$note" ]; then missing_note=1; note="（第6列没写画面说明）"; fi
  printf '%-5s %-34s %s\n' "$clip" "${text:0:16}" "$note"
done < <(/usr/bin/env python3 -c '
import json,sys
for c in json.load(open(sys.argv[1], encoding="utf-8")):
    print(c["name"] + "\t" + c.get("text",""))
' "$PROJECT/clips.json")

# 拼图：用 tile 而不是 xstack —— xstack 的 layout 表达式在这儿又长又脆，
# 先把帧按序号存成序列，交给 tile 一次拼好。
if [ "$n" -gt 0 ]; then
  seq_dir="$OUT/.seq"; mkdir -p "$seq_dir"
  i=0
  for f in "$OUT"/*.png; do
    [ -f "$f" ] || continue
    cp "$f" "$(printf '%s/f%03d.png' "$seq_dir" "$i")"; i=$((i+1))
  done
  rows=$(( (i + COLS - 1) / COLS ))
  if "$FF" -nostdin -y -v error -f image2 -i "$seq_dir/f%03d.png" \
       -vf "tile=${COLS}x${rows}:padding=6:color=#111111" -frames:v 1 "$OUT/contact.jpg" 2>/dev/null; then
    echo; echo "拼图 → $OUT/contact.jpg  （${i} 拍，${rows}×${COLS}）"
  else
    echo; echo "拼图失败，逐张看：$OUT/"
  fi
  rm -rf "$seq_dir"
fi

echo
if [ "$missing_note" = 1 ]; then
  echo "! 有拍没写第 6 列「画面说明」。把它写下来 —— 写不出来通常就意味着还没想清楚这拍要显什么。"
fi
echo "打开 contact 图逐拍对：台词说的东西，画面上有没有？没有就改 shots.tsv 的起始秒或框，别硬合成。"
echo "（图里是**源帧**，成片是 motion 参数裁过的框 —— 先确认这个时间窗里有对的东西，再调框。）"
