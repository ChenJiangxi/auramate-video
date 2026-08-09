#!/usr/bin/env bash
# package-delivery.sh — 打交付包：唯一文件名 + zip + 故事板拼图。
#
# 用法:
#   package-delivery.sh --video final-v3.mp4 [--cover cover.png] [--caption caption.txt]
#                       [--out "<选题名>-v3-交付包.zip"] [--tiles 4x3]
#
# 为什么要 zip：很多聊天前端对视频附件显示有问题（图片一直正常），zip 能稳定下载。
# 为什么要故事板：对方一定看得到图片，不一定播得了视频。
set -euo pipefail
FF=${FF:-ffmpeg}; FP=${FP:-ffprobe}
VIDEO=""; COVER=""; CAPTION=""; OUT=""; TILES="4x3"
while [ $# -gt 0 ]; do
  case "$1" in
    --video)   VIDEO="$2"; shift 2;;
    --cover)   COVER="$2"; shift 2;;
    --caption) CAPTION="$2"; shift 2;;
    --out)     OUT="$2"; shift 2;;
    --tiles)   TILES="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -f "${VIDEO:-}" ] || { echo "需要 --video <成片.mp4>" >&2; exit 2; }

BASE="$(basename "$VIDEO")"; NAME="${BASE%.*}"
case "$NAME" in
  *final*|*output*|*video*) echo "⚠ 文件名 '$BASE' 太通用 —— 同名文件会被前端缓存，对方永远看到第一版。建议改成「选题名-vN.mp4」" >&2;;
esac
grep -qE 'v[0-9]+' <<<"$NAME" || echo "⚠ 文件名里没有版本号，强烈建议加（如 -v3）" >&2

# 默认输出到成片旁边，而不是当前工作目录（不然从别处调用会把 zip 丢在意想不到的地方）
[ -n "$OUT" ] || OUT="$(cd "$(dirname "$VIDEO")" && pwd)/${NAME}-交付包.zip"
STAGE="$(dirname "$OUT")/${NAME}-交付包"
rm -rf "$STAGE"; mkdir -p "$STAGE"

cp "$VIDEO" "$STAGE/"
[ -n "$COVER" ] && [ -f "$COVER" ] && cp "$COVER" "$STAGE/" || echo "○ 没给封面（--cover）" >&2
[ -n "$CAPTION" ] && [ -f "$CAPTION" ] && cp "$CAPTION" "$STAGE/" || echo "○ 没给平台文案（--caption）" >&2

# 故事板：每 90 帧取一张（30fps ≈ 每 3 秒），拼成 TILES 格
cols="${TILES%x*}"; rows="${TILES#*x}"; n=$((cols*rows))
DUR="$($FP -v error -show_entries format=duration -of csv=p=0 "$VIDEO")"
STEP="$(awk -v d="$DUR" -v n="$n" 'BEGIN{s=int(d*30/n); if(s<1)s=1; print s}')"
"$FF" -nostdin -y -v error -i "$VIDEO" \
  -vf "select='not(mod(n,${STEP}))',scale=360:-2,tile=${TILES}" \
  -frames:v 1 -q:v 3 "$STAGE/storyboard.jpg" 2>/dev/null \
  && echo "  ✓ storyboard.jpg" || echo "  ✗ 故事板生成失败" >&2

# 用 python 打包而不是 `zip`：Info-ZIP 存中文名时不置 UTF-8 标志位，
# 到别的系统/解压器上会变乱码。zipfile 对非 ASCII 名会自动置位。
python3 -c '
import os, sys, zipfile
stage, out = sys.argv[1], sys.argv[2]
root = os.path.dirname(os.path.abspath(stage))
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for dp, _, fns in os.walk(stage):
        for fn in sorted(fns):
            p = os.path.join(dp, fn)
            z.write(p, os.path.relpath(p, root))
' "$STAGE" "$OUT"
rm -rf "$STAGE"

echo "=== 交付包 ==="
ls -lh "$OUT" | awk '{print "  " $5 "  " $NF}'
# 用 python 列内容：unzip -l 在部分环境下把中文文件名显示成乱码，误导人以为编码坏了
python3 -c '
import sys, zipfile
for i in zipfile.ZipFile(sys.argv[1]).infolist():
    if i.is_dir(): continue
    print(f"  {i.file_size/1024:9.0f} KB  {i.filename}")
' "$OUT"
echo
echo "记得：发的时候用这个唯一文件名，别复用旧名字。"
