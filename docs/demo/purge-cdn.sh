#!/usr/bin/env bash
# purge-cdn.sh — 换了 demo 视频、push 之后跑一次，让 jsDelivr 立刻拿新文件。
#
# 为什么需要：README 顶部的播放器指向 jsDelivr（GitHub 自己不能内联播仓库里的 mp4，
# raw.githubusercontent 对 mp4 返回 application/octet-stream + nosniff）。
# jsDelivr 对 @main 的缓存是 12 小时（s-maxage=43200），不刷就还是旧的。
set -euo pipefail
REPO="${REPO:-ChenJiangxi/auramate-video}"
BRANCH="${BRANCH:-main}"
FILES="${*:-docs/demo/demo.mp4 docs/demo/demo.gif docs/demo/storyboard.png docs/demo/poster.jpg}"
for f in $FILES; do
  url="https://purge.jsdelivr.net/gh/${REPO}@${BRANCH}/${f}"
  printf '  %-34s ' "$f"
  curl -s -m 30 "$url" | tr -d '\n' | head -c 120; echo
done
echo
echo "验证（应当返回 content-type: video/mp4）:"
curl -sI -m 30 "https://cdn.jsdelivr.net/gh/${REPO}@${BRANCH}/docs/demo/demo.mp4" \
  | grep -iE "^HTTP|content-type|content-length" | sed 's/^/  /'
