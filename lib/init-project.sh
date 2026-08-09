#!/usr/bin/env bash
# init-project.sh — 建一个新视频工程的标准目录 + 模板文件。
# 用法: init-project.sh <project-dir> [--slug <slug>]
set -euo pipefail
DIR="${1:-}"; [ -n "$DIR" ] || { echo "用法: init-project.sh <project-dir> [--slug xxx]" >&2; exit 2; }
shift
SLUG="$(basename "$DIR")"
[ "${1:-}" = "--slug" ] && SLUG="$2"

mkdir -p "$DIR"/{audio/samples,footage/ext,footage/rec,html/cards,html/beats,assets,work,subs}
cd "$DIR"

[ -f topic.md ] || cat > topic.md <<'EOF'
## 钩子（第一句口播，≤25 字）
<人物 + 动作 + 数字。零 context 的观众要能在 3 拍内看懂发生了什么。>

## 为什么这条能火
<点破了什么隐秘行为 / 反直觉在哪 / 情绪落点是什么>

## 落到什么功能
<选题必须和这个功能严丝合缝，不能随手挑一个>

## 调性 / 音色
<知识严肃 = presenter_male @1.28 | 情感年轻 = female-tianmei @1.24 | 营销轻快 = female-shaonv>
EOF

[ -f clips.json ] || cat > clips.json <<'EOF'
[
 {"name":"c01","text":"第一句必须是钩子，具体到人物、动作、次数。"},
 {"name":"c02","text":"第二句展开。单句不超过三十个字。"},
 {"name":"c03","text":"最后一句收品牌，不超过十五个字。"}
]
EOF

[ -f shots.tsv ] || cat > shots.tsv <<'EOF'
c01	celeb	footage/ext/REPLACE.mp4	0
c02	card	html/beats/REPLACE.webm	0
c03	full	footage/rec/REPLACE.webm	0
EOF

[ -f .gitignore ] || cat > .gitignore <<'EOF'
work/
audio/
footage/
subs/
*.mp4
*.webm
*.zip
EOF

cat <<EOF
建好了: $(pwd)

下一步:
  1. 写 topic.md（钩子 / 为什么能火 / 落到什么功能）
  2. 写 clips.json（一句 = 一拍；≤30 字；写「他/她」不写 ta）
  3. 找素材填 shots.tsv（编码器: card | full | celeb | patch）
  4. 配音:   node <repo>/lib/gen-voice.mjs --sample --text "第一句" --out audio/samples/   # 先给人挑音色
  5. 全量:   node <repo>/lib/gen-voice.mjs --clips clips.json --out audio/ --voice <选定> --speed 1.28
  6. 自检:   <repo>/lib/verify-audio.sh audio clips.json
  7. 合成:   <repo>/lib/build-vertical.sh --project . --out ${SLUG}-nosub.mp4
  8. 字幕:   /usr/bin/python3 <repo>/lib/gen-subs.py --project .
             <repo>/lib/burn-subs.sh ${SLUG}-nosub.mp4 ${SLUG}-v1.mp4
  9. 验收:   <repo>/lib/verify-output.sh ${SLUG}-v1.mp4 --expect-w 1080 --expect-h 1920 --fps 30
 10. 交付:   <repo>/lib/package-delivery.sh --video ${SLUG}-v1.mp4 --cover cover.png --caption caption.txt
EOF
