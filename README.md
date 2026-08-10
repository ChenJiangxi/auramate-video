# auramate-video — 视频制作 Skills

把「做视频」这件事拆成一组**可安装、可直接执行**的 skill。目标读者是**零 context 的 agent**：
克隆这个 repo、装上 skills、按 `skills/video-master/SKILL.md` 走，就能独立做出一条能交付的视频。

这些 skill 不是理论，是 2026-05 → 2026-08 期间做了 **60+ 条真实成片**（抖音竖版 / B 站横版 / 玄学混剪 / 产品演示）
被反复打回、返工、验收之后沉淀下来的东西。每一条「硬规矩」背后都对应一次被否掉的版本。

---

## 30 秒上手

```bash
git clone git@github.com:ChenJiangxi/auramate-video.git
cd auramate-video

# 1. 装 skills 到你的 agent（Claude Code 为例）
./install.sh ~/your-agent-dir        # 复制 skills/* 到 <agent>/.claude/skills/

# 2. 检查依赖（缺什么、缺了会卡在哪一步，一次说清）
./tests/check-deps.sh

# 3. 开工：读总纲，它会把你路由到对应的子 skill
cat skills/video-master/SKILL.md
```

**做第一条视频**（没有任何 API key 也能一路跑到底）：

```bash
lib/init-project.sh ~/work/my-first-video     # 建工程骨架，并打印后续每一步的完整命令
cd ~/work/my-first-video
# 写 topic.md 和 clips.json（怎么写见 skills/topic-and-script/）
<repo>/lib/make-placeholders.sh . --footage   # 占位配音 + 占位素材，先把管线跑通
<repo>/lib/build-vertical.sh --project . --out draft-nosub.mp4
/usr/bin/python3 <repo>/lib/gen-subs.py --project .
<repo>/lib/burn-subs.sh draft-nosub.mp4 draft-v1.mp4
<repo>/lib/audit-video.sh --project . --video draft-v1.mp4
```

管线跑通、节奏看对了，再换真配音和真素材 —— 别拿着占位素材去精修，也**别把占位配音交付出去**。

这条路径是真跑过的（干净克隆、零 key、走到 `AUDIT PASS`），完整走查和踩到的坑见
`references/zero-context-walkthrough.md`。

想验证 repo 本身没坏（会跑好几分钟渲染）：`./tests/validate.sh`

没装 `install.sh` 的 agent 也行——**直接把 `skills/video-master/SKILL.md` 全文贴进 context 就能开工**，
它内部所有引用都是 repo 内相对路径。

---

## 我要做 X → 读哪几个文件

| 我要… | 按顺序读 |
|---|---|
| **做一条抖音竖版片** | `skills/video-master/` → `skills/topic-and-script/` → `skills/vertical-shortform/` |
| **只是想先跑通看看** | README 的「做第一条视频」→ `references/zero-context-walkthrough.md` |
| **想选题 / 写口播稿** | `skills/topic-and-script/`（角度库 + 钩子句式 + 实测语速） |
| **确认这题材能不能做** | `skills/compliance-redlines/`（先过这关，再谈别的） |
| **扒外部真实素材** | `skills/real-clip-mashup/` → `lib/fetch-clip.sh` → `lib/fit-vertical.sh` |
| **录自家产品界面** | `skills/product-demo/` → `lib/rec-page.js` → `lib/zoom-crop.sh` → `lib/wrap-chrome.sh` |
| **做大字卡 / 数据榜** | `skills/html-motion-cards/` → `lib/storyboard.js` |
| **配音** | `skills/tts-voiceover/` → `lib/gen-voice.mjs` |
| **加字幕** | `skills/subtitles/` → `lib/gen-subs.py` + `lib/burn-subs.sh` |
| **出封面** | `skills/cover-thumbnail/` → `lib/make-cover.py` |
| **ffmpeg 参数记不清** | `skills/ffmpeg-cookbook/`（配方 + 报错速查） |
| **交付前自审** | `skills/quality-gate/` → `lib/audit-video.sh` |
| **打交付包** | `skills/delivery/` → `lib/package-delivery.sh` |
| **做 B 站横版长片** | `references/bilibili-longform.md` |
| **写平台文案** | `references/caption-template.md` |

---

## 目录

| 路径 | 是什么 |
|---|---|
| `skills/video-master/` | **总纲**。合规红线 + 硬规矩 + 选题路由 + 8 阶段管线 + 验收清单。**先读这个。** |
| `skills/compliance-redlines/` | **合规红线**。命理/玄学题材的违规边界、词表、安全表达框架。优先级最高 |
| `skills/topic-and-script/` | **选题与脚本**。决定 80% 的那一环：角度库、钩子句式、实测语速、文案模板 |
| `skills/vertical-shortform/` | 竖版短视频（抖音 / 小红书，1080×1920，40–60s）完整管线 |
| `skills/real-clip-mashup/` | 真人切片混剪：yt-dlp 扒真实素材 → 竖版化 → 混剪 |
| `skills/product-demo/` | 产品录屏演示：素材盘点 → 录屏 → 裁切放大 → 假浏览器壳 |
| `skills/html-motion-cards/` | HTML/CSS 动效卡：5 套模板 + 公共设计系统 + storyboard 驱动渲染 |
| `skills/tts-voiceover/` | 配音：MiniMax T2A v2、克隆音 / 系统音色、语速、读音坑 |
| `skills/subtitles/` | 字幕：PIL overlay（无 libass 环境）+ ASS 两条路 |
| `skills/cover-thumbnail/` | 封面：爆款风巨字 + 戏剧图 + 副标 |
| `skills/quality-gate/` | **交付前质量闸门**：一条命令跑完机械检查 + 17 条真实被打回案例 |
| `skills/delivery/` | 交付：唯一文件名 + zip + 故事板图 + faststart |
| `skills/ffmpeg-cookbook/` | ffmpeg 配方库：竖版化、zoompan、concat、mux、探测 |
| `lib/` | 可直接复制到项目里跑的脚本模板（扒素材 / 竖版化 / build / 配音 / 字幕 / 封面 / 合规 / 探测） |
| `examples/` | 最小可跑样例，不需要任何 API key |
| `references/` | 长文参考：零 context 走查、B 站横版长视频、平台文案模板 |
| `tests/validate.sh` | 自检：frontmatter、死链、脚本/合规 linter、样例能出片、零 key 冒烟 |
| `tests/check-consistency.py` | 一致性：孤儿脚本 / 路由完整 / README 覆盖 / **旧说法不许复活** |
| `SECRETS-CHECKLIST.md` | **需要人类通过 prompt 传入的密钥清单**（repo 内只有占位符，无真值） |

---

## 依赖

必须：

- `ffmpeg` + `ffprobe`（**注意**：部分 Homebrew 构建不带 libass，字幕要走 PIL overlay 路线，见 `skills/subtitles/`）
- `python3` + `Pillow`（字幕、封面、图片补丁）

按需：

- `node` ≥ 18 + `playwright`（产品录屏）
- `yt-dlp`（扒真实切片素材）
- MiniMax API key（配音）——见 `SECRETS-CHECKLIST.md`

自检命令：

```bash
./tests/check-deps.sh
```

---

## 这套东西的三条底层原则

1. **真实 > 精致。** 真人切片、真实产品录屏、真实数据，永远赢过我自己画的动效卡。
   被打回最多的一类版本就是「全是 HTML 卡」。
2. **数据绝不编。** 涉及测评分数、准确率、统计的数字，只用委托方真跑出来的值。
   自己画图（渲染）可以，自己编数字绝不。
3. **交付前留人类审核点。** 配音够不够有情绪、创意对不对味，agent 判断不了。
   工作流的作用是让人类的判断执行得飞快，不是取代它。

还有一条优先级更高的前置条件：**合规**。
宣扬封建迷信必违规；讲 AI 算命、讲产品功能不违规。做命理题材前先读
`skills/compliance-redlines/`，并对每条片子跑 `lib/check-compliance.py`。

---

## 贡献 / 演进

每条新踩的坑 → 写进对应 skill 的「失败症状 → 修法」表。
不要新开一个 `NOTES.md`，坑必须落在**会被读到的那个 skill 里**。
