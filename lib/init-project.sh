#!/usr/bin/env bash
# init-project.sh — 建一个新视频工程的标准目录 + 模板文件。
# 用法: init-project.sh <project-dir> [--slug <slug>]
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"   # 打印真实路径，别让读的人自己猜 <repo> 是什么
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
repo:   ${REPO}

写内容:
  1. topic.md   钩子 / 为什么能火 / 落到什么功能 / 安全框     → skills/topic-and-script
  2. clips.json 一句 = 一拍；写「他/她」不写 ta
  3. 两道闸门（定稿就跑，别攒到最后）:
       /usr/bin/python3 ${REPO}/lib/check-script.py     --project . --target 40-60
       /usr/bin/python3 ${REPO}/lib/check-compliance.py --project .

还没有 API key / 还没找到素材？先跑占位，把管线和节奏验对再花钱:
  ${REPO}/lib/make-placeholders.sh . --footage
  （占位配音时长按实测语速算，粗剪节奏跟成片接近；🔴 绝不能交付）

有 key 之后:
  4. 音色采样让人挑: node ${REPO}/lib/gen-voice.mjs --sample --text "第一句" --out audio/samples/
  5. 全量配音:       node ${REPO}/lib/gen-voice.mjs --clips clips.json --out audio/ --voice <选定> --speed 1.28
  6. 配音自检:       ${REPO}/lib/verify-audio.sh audio clips.json   # 通过后删掉 audio/.placeholder

素材（按目录约定摆，audit 靠它统计画面构成）:
  footage/ext/ 真实切片   footage/rec/ 产品录屏   html/beats/ 卡片
  外部切片: ${REPO}/lib/fetch-clip.sh search "关键词" → get → probe（抽帧看水印！）→ fit-vertical.sh
  产品录屏: ${REPO}/lib/rec-page.js → ${REPO}/lib/zoom-crop.sh
  动效卡:   写 storyboard.json → node ${REPO}/lib/storyboard.js --project .

出片:
  7. 合成:   ${REPO}/lib/build-vertical.sh --project . --out ${SLUG}-nosub.mp4
  8. 字幕:   /usr/bin/python3 ${REPO}/lib/gen-subs.py --project .
             ${REPO}/lib/burn-subs.sh ${SLUG}-nosub.mp4 ${SLUG}-v1.mp4
  9. 验收:   ${REPO}/lib/audit-video.sh --project . --video ${SLUG}-v1.mp4 --target 40-60
             （机器项全过 ≠ 能发，人工那张清单必须真的过一遍）
 10. 交付:   ${REPO}/lib/package-delivery.sh --video ${SLUG}-v1.mp4 --cover cover.png --caption caption.txt
EOF
