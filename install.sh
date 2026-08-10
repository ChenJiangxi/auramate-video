#!/usr/bin/env bash
# install.sh — 把这套 skill 接到一个 agent 上。
#
# 不同 agent 认的约定不一样，所以分 target：
#
#   ./install.sh claude  <agent-dir>      复制 skills/* 到 <dir>/.claude/skills/
#                                          （Claude Code 会按 frontmatter 自动路由）
#   ./install.sh codex   <project-dir>    在工程目录写一份 AGENTS.md
#                                          （Codex CLI / Cursor 等只读 AGENTS.md，
#                                            不认 .claude/skills/）
#   ./install.sh bundle  <out.md>         把总纲 + 全部子 skill 拼成**一个文件**
#                                          （给只能吃单份 prompt 的 agent）
#
# 兼容老用法：./install.sh <agent-dir> [--symlink] 等价于 claude target。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

usage(){ sed -n '2,18p' "$0"; exit 2; }
TARGET="${1:-}"; [ -n "$TARGET" ] || usage

case "$TARGET" in
  claude|codex|bundle) DEST="${2:-}"; shift 2 2>/dev/null || true;;
  *) DEST="$TARGET"; TARGET=claude; shift 1;;      # 老用法
esac
[ -n "${DEST:-}" ] || usage

# ---------------------------------------------------------------- claude
if [ "$TARGET" = claude ]; then
  [ -d "$DEST" ] || { echo "目录不存在: $DEST" >&2; exit 2; }
  MODE=copy; [ "${1:-}" = "--symlink" ] && MODE=symlink
  D="$DEST/.claude/skills"; mkdir -p "$D"
  n=0
  for d in "$ROOT"/skills/*/; do
    name="$(basename "$d")"; rm -rf "$D/$name"
    if [ "$MODE" = symlink ]; then ln -s "$d" "$D/$name"; else cp -R "$d" "$D/$name"; fi
    echo "  ✓ $name"; n=$((n+1))
  done
  echo
  echo "装了 $n 个 skill 到 ${D}（${MODE}）"
  echo "lib/ 没复制 —— 用绝对路径调用：${ROOT}/lib/..."
  echo "下一步: ${ROOT}/setup.sh --check"
  exit 0
fi

# ---------------------------------------------------------------- codex
if [ "$TARGET" = codex ]; then
  mkdir -p "$DEST"
  OUT="$DEST/AGENTS.md"
  if [ -f "$OUT" ]; then
    cp "$OUT" "$OUT.bak"
    echo "  ! 已存在 AGENTS.md，备份成 AGENTS.md.bak"
  fi
  sed "s|__REPO__|${ROOT}|g" "$ROOT/templates/AGENTS.md.tpl" > "$OUT"
  echo "  ✓ 写入 $OUT"
  echo
  echo "Codex CLI 会自动读工程目录里的 AGENTS.md。开工："
  echo "  cd $DEST && codex"
  echo
  echo "配音需要 key（不进 repo，走环境变量）："
  echo "  export MINIMAX_API_KEY=...        # 见 ${ROOT}/SECRETS-CHECKLIST.md"
  echo "没有 key 也能跑通全流程，占位配音顶上。"
  exit 0
fi

# ---------------------------------------------------------------- bundle
if [ "$TARGET" = bundle ]; then
  mkdir -p "$(dirname "$DEST")"
  {
    echo "# 做视频 · 全量 skill 单文件版"
    echo
    echo "> 由 install.sh bundle 生成。脚本在 \`${ROOT}/lib/\`，用绝对路径调用。"
    echo "> 完整仓库：https://github.com/ChenJiangxi/auramate-video"
    echo
    echo "开工前先跑 \`${ROOT}/setup.sh --check\` 看具备哪些能力。"
    echo
    echo "---"
    # 总纲排第一，其余按名字排。用 python 剥 frontmatter —— BSD sed 拼不出这个表达式
    /usr/bin/env python3 - "$ROOT" <<'PYBUNDLE'
import glob, os, sys
root = sys.argv[1]
files = [os.path.join(root, 'skills/video-master/SKILL.md')]
files += sorted(f for f in glob.glob(os.path.join(root, 'skills/*/SKILL.md'))
                if 'video-master' not in f)
for f in files:
    t = open(f, encoding='utf-8').read()
    if t.startswith('---\n'):                      # 剥掉 frontmatter
        t = t.split('---\n', 2)[2]
    print('\n---\n')
    print(t.strip())
PYBUNDLE
  } > "$DEST"
  words=$(wc -c < "$DEST" | tr -d ' ')
  echo "  ✓ $DEST"
  echo "  约 $((words / 1024)) KB / 粗估 $((words / 2)) tokens（中文约 2 字节 1 token）"
  echo
  echo "把它整份贴进 agent 的 context 就能开工；脚本路径已经是绝对路径。"
  exit 0
fi

usage
