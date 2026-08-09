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

### ✅ Run 1.5 — 合规红线（2026-08-10，Jessy 现场提出，插队做）

- [x] `skills/compliance-redlines/` —— 一句话原则「宣扬封建迷信必违规；讲 AI 算命、
      讲产品功能不违规」+ 七类必删 + 高风险清单 + 四个安全表达框（技术/文化/产品/心理）
      + 逐词替换表 + 交付前三问
- [x] `lib/check-compliance.py` —— BLOCK / WARN / INFO 三档 linter，扫 clips.json +
      topic.md + caption.txt，有 BLOCK 退出码 1
- [x] `tests/fixtures/compliance-{bad,good}/` + validate.sh 断言（违规样本必须被拦、
      合规样本不许误报、样例工程自身必须合规）
- [x] 接进主干：video-master §3 合规红线（优先级高于硬规矩）、vertical-shortform
      阶段①②⑧ 三处闸门、delivery 交付前检查、README

### ✅ Run 2 — 选题与脚本（2026-08-10）

- [x] 新 skill `skills/topic-and-script/`：四框角度库（12 条真实交付选题拆解）、
      6 个已验证钩子句式 + 具体性自检、clips.json 分句规则、结构时间预算、
      平台文案模板、常见废稿特征、失败症状表
- [x] 选题阶段就落「四个安全表达框」，`topic.md` 模板加了「安全框」一节
- [x] `lib/check-script.py`：单拍时长 / 单句字数 / `ta` / 钩子具体性 / 末句收品牌 /
      句式重复 / 框定话术，硬错误退出码 1
- [x] `references/caption-template.md`：真实交付格式 + 样例 + 三条规矩
- [x] `examples/hello-vertical/topic.md` 补成真样例（含镜头表）
- [x] **实测语速**替换掉拍脑袋的 5 字/秒（video-master / vertical-shortform 都改了）

（角度库目前是 12 条真实做过的拆解，不是「每框 10 个待做选题」——
待做选题清单留到 Run 8 收尾时补，先把已验证的沉淀下来更有价值。）

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
| 1.5 | 2026-08-10 | ✅ OK | ✅ 同上（未回归） | 合规 linter 三项断言全过；历史真实口播稿回测无误报 |
| 2 | 2026-08-10 | ✅ OK | ✅ 1080×1920 / 11.35s / h264+aac / 30fps | 脚本 linter 三项断言全过；回测揪出我自己定错的 3 条规则 |

### Run 2 自测记录（选题与脚本）

**跑了什么**

- `validate.sh` 全绿，新增「脚本 linter」三条断言：真实交付稿必须放行（防阈值过严）、
  坏稿必须被拦、样例工程必须通过。
- 端到端渲染回归通过（1080×1920 / 11.35s / h264+aac / 30fps）。

**回测真实数据揪出的问题 —— 我上一轮自己定错了 3 条规则**

拿真实发过的稿子（`xuanxue-loop` v23，实测 52.31s）和 `laowai-zhun`（89.2s）回测：

1. **语速错了 27%。** 我写的是「5 字/秒」，实测 **6.35 字/秒**（含标点，presenter_male@1.30）；
   克隆音 @1.10 是 4.98。按 5 写的 75s 稿子实际只有 59s。已换成实测表，
   并注明留出法校验误差 8.8%（前 5 句拟合预测后 4 句）——估算只能到 ±10%，配完音必须实测。
2. **「单句 ≤30 字」是错的。** 真实交付稿 9 句里有 4 句超 30 字（43/61/37/60），
   横版稿甚至有 88 字的句子，全都正常交付。真正的约束是**一拍占多长画面**
   （实测最长一拍：竖版 10.04s / 横版 19.09s）。linter 改成按单拍时长判硬错误（>15s），
   字数只做提示（>45 字）。
3. **「末句 ≤15 字」是错的。** 实测末句往往是**全片最长**的一句（要把产品讲完，60 字）。
   改成检查「末句有没有收品牌」，不卡字数。

这三条都是我上一轮凭印象写的，回测才发现和实际交付内容矛盾。
`validate.sh` 现在有一条常驻断言：**真实交付稿必须被放行**，防止以后再把阈值定得比现实还严。

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

### Run 1.5 自测记录（合规）

- `validate.sh` 新增三条断言全过：违规样本命中 8 条 BLOCK 被拦下（exit 1）、
  合规样本零误报（exit 0）、样例工程 `hello-vertical` 自身合规。
- **拿真实历史成片回测**（这才是词表有没有用的真检验）：
  `xuanxue-loop/clips.json`（AI 考命理）和 `deliver-tijian2/文案.txt`（命理体检 × 中医，
  医疗风险最高的一条）都是 **0 BLOCK / 0 WARN** —— 词表对真实内容没有误报。
- **回测发现的真问题**：过去的口播稿**基本没有框定话术**（xuanxue-loop 那条完全没有）。
  也就是说以前全靠选题本身安全，没有主动把结果定性为「参考 / 自我觉察 / 传统文化说法」。
  这条已写进 skill，linter 现在会以 INFO 提醒。

**已知不足（下一轮处理）**

- `rec-page.js` / `render-card.js` 只做了语法校验，**没跑过真实站点**（需要凭据 + 目标站）。
- `gen-voice.mjs` **没跑过真实 API**（需要 key）。逻辑按现役脚本移植 + 加了报错码提示。
- 语速表只有 2 个音色的样本；`female-tianmei` / `female-shaonv` 还没实测过。
