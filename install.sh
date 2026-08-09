#!/usr/bin/env bash
# install.sh — 把 skills 装进一个 agent 目录。
# 用法: ./install.sh <agent-dir> [--symlink]
#   默认复制；--symlink 建软链（本机开发时用，repo 一改 agent 立刻生效）
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "用法: ./install.sh <agent-dir> [--symlink]" >&2; exit 2; }
[ -d "$TARGET" ] || { echo "目录不存在: $TARGET" >&2; exit 2; }
MODE="copy"; [ "${2:-}" = "--symlink" ] && MODE="symlink"

DEST="$TARGET/.claude/skills"
mkdir -p "$DEST"

n=0
for d in "$ROOT"/skills/*/; do
  name="$(basename "$d")"
  rm -rf "$DEST/$name"
  if [ "$MODE" = "symlink" ]; then ln -s "$d" "$DEST/$name"; else cp -R "$d" "$DEST/$name"; fi
  echo "  ✓ $name"
  n=$((n+1))
done

echo
# 注意：变量后面紧跟全角标点必须用 ${} 包起来，否则 bash 会把全角字节当成变量名的一部分
echo "装了 $n 个 skill 到 ${DEST}（${MODE}）"
echo
echo "lib/ 脚本没有复制 —— 用绝对路径调用即可:"
echo "  $ROOT/lib/build-vertical.sh --project <你的工程> ..."
echo
echo "下一步: $ROOT/tests/check-deps.sh"
