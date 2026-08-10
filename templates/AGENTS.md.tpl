# AGENTS.md — 做视频

你现在这个目录是一个**视频工程**。做视频的全部规矩和脚本在：

```
__REPO__
```

`__REPO__/skills/` 下每个目录是一个 skill（一份 `SKILL.md`），`__REPO__/lib/` 下是可直接跑的脚本。
**需要哪份就 `cat` 哪份**，别凭印象干。

---

## 开工前

```bash
__REPO__/setup.sh --check        # 看你现在具备哪些能力（剪辑/字幕/配音/录屏/扒素材）
```

缺能力不等于不能干：**只要「剪辑合成 + 字幕 + 占位配音」在，就能跑通全流程出粗剪**。
真配音需要 `MINIMAX_API_KEY`，产品录屏需要 playwright + 目标站凭据 —— 缺就先用占位，别停。

---

## 第一件事：读总纲

```bash
cat __REPO__/skills/video-master/SKILL.md
```

它是入口，会把你路由到该用的子 skill。**下面这几条是从总纲里摘的，违反必被打回**：

1. **合规优先于一切**（命理/玄学题材）。宣扬封建迷信必违规；讲 AI 算命、讲产品功能不违规。
   选题定了先跑 `check-compliance.py`，有 BLOCK 就别往下做。
2. **真实素材 > 自己画的卡。** 卡只能当标题/钩子/数据展示，**不许整片都是卡**。
3. **数字绝不编。** 测评分数、统计数字只用真跑出来的值。
4. **音频驱动时间轴。** 先配音，用 `ffprobe` 量每句时长，视频每一拍 = 这句配音 + 0.25s。
   反过来做必然出现「画面停在那儿死寂几秒」。
5. **别升采样过头。** 源比目标窄多少就要放大多少，>1.3× 开始糊、>2× 没法看。
   拿不准就用 `fit` 编码器（自动封顶）。
6. **字幕在下三分之一（Y≈1400），1:1 跟每一句，不许漏行。**
7. **交付前跑 `audit-video.sh`**，并把它输出的「只有人能判的」那张清单原样交给人类。
   机器项全过 ≠ 能发。

---

## 路由：我要做 X → 读哪份

| 要做的事 | `cat` 这个 |
|---|---|
| 选题 / 写口播稿 | `__REPO__/skills/topic-and-script/SKILL.md` |
| 确认题材能不能做 | `__REPO__/skills/compliance-redlines/SKILL.md` |
| 竖版短视频完整管线 | `__REPO__/skills/vertical-shortform/SKILL.md` |
| 扒外部真实切片 | `__REPO__/skills/real-clip-mashup/SKILL.md` |
| 录自家产品界面 | `__REPO__/skills/product-demo/SKILL.md` |
| 大字卡 / 数据榜 | `__REPO__/skills/html-motion-cards/SKILL.md` |
| 配音 | `__REPO__/skills/tts-voiceover/SKILL.md` |
| 字幕 | `__REPO__/skills/subtitles/SKILL.md` |
| 封面 | `__REPO__/skills/cover-thumbnail/SKILL.md` |
| ffmpeg 参数记不清 | `__REPO__/skills/ffmpeg-cookbook/SKILL.md` |
| 交付前自审 | `__REPO__/skills/quality-gate/SKILL.md` |
| 打交付包 | `__REPO__/skills/delivery/SKILL.md` |

---

## 命令速查（在本工程目录里跑）

```bash
R=__REPO__

# 1. 建骨架（如果这个目录还是空的）
$R/lib/init-project.sh .

# 2. 写 topic.md 和 clips.json 之后，两道闸门
/usr/bin/python3 $R/lib/check-script.py     --project . --target 40-60
/usr/bin/python3 $R/lib/check-compliance.py --project .

# 3. 没有 key / 没有素材 —— 先跑占位，把管线和节奏验对
$R/lib/make-placeholders.sh . --footage

# 3'. 有 key 的真配音（先出 3 个音色候选让人类挑，别自己拍板）
node $R/lib/gen-voice.mjs --sample --text "第一句" --out audio/samples/
node $R/lib/gen-voice.mjs --clips clips.json --out audio/ --voice presenter_male --speed 1.28 --force
$R/lib/verify-audio.sh audio clips.json && rm -f audio/.placeholder

# 4. 素材（按目录约定摆：footage/ext=真实切片 footage/rec=产品录屏 html/beats=卡）
$R/lib/fetch-clip.sh search "关键词" -n 8
$R/lib/fetch-clip.sh get <url> -o footage/ext/x.mp4
$R/lib/fetch-clip.sh probe footage/ext/x.mp4 --need 4.2   # 打开 contact 图看水印！
node $R/lib/storyboard.js --project .                     # 卡：写 storyboard.json 后渲染

# 5. 合成 → 字幕 → 审计
$R/lib/build-vertical.sh --project . --out draft-nosub.mp4
/usr/bin/python3 $R/lib/gen-subs.py --project . --skip <自带大字的拍>
$R/lib/burn-subs.sh draft-nosub.mp4 draft-v1.mp4 --manifest subs/manifest.tsv
$R/lib/audit-video.sh --project . --video draft-v1.mp4 --target 40-60

# 6. 交付
$R/lib/package-delivery.sh --video draft-v1.mp4 --cover cover.png --caption caption.txt
```

`shots.tsv` 每行：`clip <TAB> 编码器 <TAB> 素材路径 <TAB> 起始秒`
编码器：`card`（已是竖版的卡）· `fit`（拿不准就用它，自动防糊）· `full`（源够清晰的竖版）·
`celeb`（横屏切片，模糊垫底）· `patch`（录屏 + 图片补丁）

---

## 留给人类的审核点（别自己拍板）

- 音色：生成 3 个候选让人类挑
- 配音够不够有情绪：你听不到成品音
- 创意 / 这条能不能火：只能给方案

交付时把 `audit-video.sh` 的「只有人能判的」清单原样附上。
