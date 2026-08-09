# PROGRESS — 循环任务路线图

每小时一轮，一轮聚焦一个主题做透，做完自测 → push → 报结果。
**下一轮开工先读这个文件，取第一个未打勾的条目。**

## 完成条件（全部满足才停）

- [ ] 规划中的所有子 skill 都完成「深度展开」（不只是骨架）
- [ ] `tests/validate.sh` 全绿（含端到端渲染）
- [ ] 零 context agent 冒烟测试通过（只给 repo，能独立做出一条合规视频）
- [ ] 已推送到 `origin main`
- [ ] `SECRETS-CHECKLIST.md` 已交付给人类

---

## Roadmap

### ✅ Run 1 — 骨架 + 主干 + 可验证性（2026-08-10）

- [x] repo 骨架：README / INSTALL(install.sh) / .gitignore / PROGRESS
- [x] `skills/video-master/` 总纲：硬规矩 H1–H11、路由表、8 阶段管线、验收清单、症状表
- [x] `skills/vertical-shortform/` 竖版主干管线（audio-driven、4 个编码器、concat、音轨防漂移）
- [x] `lib/build-vertical.sh` 参数化合成（clips.json + shots.tsv 驱动）
- [x] `lib/gen-subs.py` / `lib/burn-subs.sh` 字幕（PIL overlay 路线）
- [x] `lib/gen-voice.mjs` 配音（含音色采样模式、报错码提示）
- [x] `lib/verify-audio.sh` / `lib/verify-output.sh` 机械自检
- [x] `lib/init-project.sh` / `lib/package-delivery.sh` / `lib/make-cover.py` / `lib/make-brand-assets.py`
- [x] `lib/rec-page.js` / `lib/render-card.js`
- [x] 其余 8 个子 skill 首版（tts-voiceover / subtitles / real-clip-mashup / product-demo /
      html-motion-cards / cover-thumbnail / delivery / ffmpeg-cookbook）
- [x] `references/bilibili-longform.md`
- [x] `tests/check-deps.sh` + `tests/validate.sh`（结构 / 死链 / 语法 / 泄密扫描 / 端到端渲染）
- [x] `examples/hello-vertical/` 零 key 可跑样例
- [x] `SECRETS-CHECKLIST.md`

### Run 2 — 选题与脚本（这是最缺的一环）

- [ ] 新 skill `skills/topic-and-script/`：选题公式、钩子模板库、
      「点破用户隐秘行为」批量选题法、脚本节奏（3 拍讲清一个故事）、
      字数↔时长换算、镜头表模板、常见废稿特征
- [ ] `lib/check-script.py`：机械检查 clips.json（字数/单句长度/"ta"/钩子具体性/句数）
- [ ] 把 `examples/hello-vertical/topic.md` 补成真样例

### Run 3 — real-clip-mashup 深化

- [ ] 素材检索策略（关键词构造、候选筛选、版权与水印判定）
- [ ] `lib/fetch-clip.sh`：yt-dlp 封装（h264 强制、站点 header、抽帧预览、时长校验）
- [ ] 竖版化参数表（不同源画幅 → 前景高度/位置查表）

### Run 4 — product-demo 深化

- [ ] 录屏前的「素材盘点 → 缺口清单 → 现录计划」流程
- [ ] `lib/zoom-crop.sh`：按元素定位自动裁切放大
- [ ] `lib/browser-chrome.py` + `lib/wrap-chrome.sh`：假浏览器壳（横版演示片）

### Run 5 — html-motion-cards 深化

- [ ] 卡模板库（hook 大字 / 数据卡 / 榜单 / 对比 / CTA）实际 HTML 文件
- [ ] data-attr 驱动的 storyboard → 自动生成 concat 清单 + 字幕时间戳
- [ ] `lib/storyboard.js`

### Run 6 — 质量闸门与自审

- [ ] 新 skill `skills/quality-gate/`：交付前自审流程（机器检查 + 人工检查分开）
- [ ] `lib/audit-video.sh`：一条命令跑完所有机械检查并出报告
- [ ] 「什么样的版本会被打回」案例库

### Run 7 — 零 context 冒烟测试

- [ ] 在干净目录里，只给 repo + SECRETS-CHECKLIST，走一遍完整流程
- [ ] 记录卡住的每一处 → 回填到对应 skill
- [ ] 重复直到能一次跑通

### Run 8+ — 收尾

- [ ] 全 repo 交叉引用检查、术语统一
- [ ] README 加「按角色导航」（我要做 X → 读哪几个文件）
- [ ] 把每轮踩的新坑回填进各 skill 的「失败症状 → 修法」表

---

## 每轮自测结论

| Run | 日期 | validate.sh | 端到端渲染 | 备注 |
|---|---|---|---|---|
| 1 | 2026-08-10 | ✅ OK | ✅ 1080×1920 / 11.35s / h264+aac / 30fps | 见下方 Run 1 自测记录 |

### Run 1 自测记录（2026-08-10 03:2x）

**跑了什么**

- `tests/check-deps.sh` —— 本机 ffmpeg 8.1.1 **无 libass**（已确认），字幕走 PIL overlay 是对的路线。
- `tests/validate.sh` 全绿：10 个 skill 结构 / 43 处内部引用无死链 / 35 个文件泄密扫描 / 16 个脚本语法 /
  端到端渲染出片并 ffprobe 校验。
- 额外手测：`install.sh`（装进临时 agent 目录，10 个 skill）、`init-project.sh`（建工程骨架）、
  `make-cover.py`（1080×1440 封面，抽帧看过版式正确）、`package-delivery.sh`（zip + 故事板，
  `ditto` 解压中文名正常）、`gen-subs.py --no-merge`（钩子拆三拍，时间轴首尾对齐 11.35s）。
- 抽帧目视：`celeb` 编码器的模糊背景+主体居中正确，字幕落在 Y=1400 下三分之一。

**这一轮真修掉的 bug**（都是自测跑出来的，不是想出来的）

1. `verify-audio.sh` 用了 `ffmpeg -v error` 跑 `volumedetect` —— 统计走 info 级日志，被吞掉后
   把正常音频全判成静音。已改 `-hide_banner -nostats`，并在解析不到时不瞎判。
2. `install.sh` 里 `$DEST（` —— bash 把全角括号的字节吞进变量名，报 `unbound variable`。
   已改 `${DEST}`，并把这条加进 `validate.sh` 作为常驻检查（又揪出 2 处同类）。
3. `package-delivery.sh` 用 `zip` 打包中文名不置 UTF-8 标志位 → 换解压器变乱码。改用 python
   `zipfile`（自动置位），实测 `ditto` 解压中文名正常。
4. `package-delivery.sh` 默认输出落在当前工作目录而不是成片旁边 —— 从别处调用会把 zip 丢错地方。已改。
5. `build-vertical.sh` 用了 `mapfile`（bash 4+），macOS 自带 bash 3.2 跑不了。已换 while-read。

**已知不足（下一轮处理）**

- 选题/脚本环节还没有专门的 skill —— 这是最缺的一环（Run 2）。
- `rec-page.js` / `render-card.js` 只做了语法校验，**没跑过真实站点**（需要凭据 + 目标站）。
- `gen-voice.mjs` **没跑过真实 API**（需要 key）。逻辑按现役脚本移植 + 加了报错码提示。
