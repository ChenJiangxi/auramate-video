# 零 context 冒烟走查

**这条路径是真跑过的**：干净目录、干净克隆、**没有任何 API key**，
从零走到 `AUDIT PASS`。`tests/validate.sh` 里有一段常驻断言每次都重跑它，
所以它不会悄悄坏掉。

---

## 完整路径（照抄就行）

```bash
# ① 拿到 repo
git clone git@github.com:ChenJiangxi/auramate-video.git
cd auramate-video
REPO=$(pwd)

# ② 装 skills（可选；不装就直接把 skills/video-master/SKILL.md 贴进 context）
./install.sh ~/your-agent-dir

# ③ 查依赖 —— 缺什么、缺了卡在哪一步，一次说清
./tests/check-deps.sh

# ④ 建工程。它会打印**真实路径**的后续每一步命令，不用自己猜
$REPO/lib/init-project.sh ~/work/my-first-video
cd ~/work/my-first-video

# ⑤ 写 topic.md + clips.json（怎么写见 skills/topic-and-script/）

# ⑥ 两道闸门，定稿就跑
/usr/bin/python3 $REPO/lib/check-script.py     --project . --target 40-60
/usr/bin/python3 $REPO/lib/check-compliance.py --project .

# ⑦ 没有 key / 没有素材 —— 先跑占位，把管线和节奏验对
$REPO/lib/make-placeholders.sh . --footage

# ⑧ 一路出片
$REPO/lib/build-vertical.sh --project . --out draft-nosub.mp4
/usr/bin/python3 $REPO/lib/gen-subs.py --project .
$REPO/lib/burn-subs.sh draft-nosub.mp4 draft-v1.mp4 --manifest subs/manifest.tsv

# ⑨ 审计
$REPO/lib/audit-video.sh --project . --video draft-v1.mp4 --target 40-60
```

到这里你会拿到一条 1080×1920 的**粗剪**，节奏跟成片接近（占位音时长按实测语速算）。

然后才是花钱和花力气的部分：

```bash
# 真配音（需要 key，见 SECRETS-CHECKLIST.md）
node $REPO/lib/gen-voice.mjs --sample --text "第一句" --out audio/samples/   # 先让人挑音色
node $REPO/lib/gen-voice.mjs --clips clips.json --out audio/ --voice <选定> --speed 1.28 --force
rm audio/.placeholder                     # ← 别忘了

# 真素材
$REPO/lib/fetch-clip.sh search "关键词" -n 8
$REPO/lib/fetch-clip.sh get <url> -o footage/ext/x.mp4
$REPO/lib/fetch-clip.sh probe footage/ext/x.mp4 --need 4.2   # 打开 contact 图看水印！
$REPO/lib/fit-vertical.sh footage/ext/x.mp4 work/v01.mp4 --dur 4.2 --ss 12
```

---

## 这次走查发现并修掉的 5 处卡壳

记在这里，是因为**它们都是「文档看着通、真跑就断」的那种**。

| # | 卡在哪 | 根因 | 修法 |
|---|---|---|---|
| 1 | **没有 API key 就完全走不下去** | 整条管线 audio-driven，没配音连 build 都起不来；repo 里只有 `examples/` 有占位素材，且写死在那个例子里 | 新增 `lib/make-placeholders.sh`，任意工程都能造占位配音 + 占位素材 |
| 2 | `init-project.sh` 打印字面量 `<repo>` | 脚本知道自己在哪却没用上 | 改成打印真实绝对路径，并把后续每一步的完整命令列全 |
| 3 | `shots.tsv` 模板只有 3 行，写了 5 句就 build 失败 | 模板固定行数，不跟 `clips.json` 走 | `make-placeholders.sh --footage` 会**补齐缺的拍** |
| 4 | README「30 秒上手」第 2 步写 `tests/validate.sh` 却注释成「检查依赖」 | 名实不符，而且它要跑好几分钟渲染 | 改成 `tests/check-deps.sh`；validate 移到「想验证 repo 没坏」那句 |
| 5 | 占位配音会**静默通过 audit** | `verify-audio` 只看时长和响度，正弦音全过 | `make-placeholders` 留 `audio/.placeholder` 标记，`audit-video.sh` 单独点名警告 |

---

## 常驻断言

`tests/validate.sh` 的「零 context 冒烟」一节每次都会：

1. `init-project.sh` 建全新工程，并检查输出里**不许出现字面量 `<repo>`**；
2. 故意写 5 句（比模板的 3 行多），检查 `shots.tsv` 缺的拍**被自动补齐**；
3. 全程无 key 走到出片，校验 1080×1920；
4. 跑 `audit-video.sh`，检查它**点名了占位配音**。

任何一条断了就是回归——说明零 context 的路径又被弄坏了。

---

## 还没验证过的部分（诚实说明）

只剩一条：**克隆音（`voice_id` 私有）没测过**，只实测了三个系统音色的语速。

`render-card.js` 单张卡（webm / `--png`）已进 `validate.sh` 常驻断言。

`rec-page.js` 和 `rec-frames.js` 都已在真实站点验过：登录 → 录屏 → 产品界面；
`rec-frames.js` 还带光标和动作表跑通过真实点击（点大运 → 面板展开 → 点流年），
`--desktop` + 强调层（暗场 / 高亮框 / 记号笔 / 标注气泡）也在真实站点上录过 16:9。

`gen-voice.mjs` 已在真实 MiniMax 接口上跑通（国际区 `api.minimax.io`），
三个系统音色的实测语速已回填进 `skills/topic-and-script/` 和 `skills/tts-voiceover/`。
