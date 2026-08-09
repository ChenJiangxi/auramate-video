# hello-vertical — 最小可跑样例

跑通一次完整竖版管线，**不需要任何 API key**（配音用正弦占位、素材用 ffmpeg 生成）。
先让管线跑绿，再把 `audio/` 换成真配音、`footage/` 换成真素材。

```bash
cd examples/hello-vertical

./make-fixtures.sh                                  # 造假素材 + 假配音
../../lib/verify-audio.sh audio clips.json          # 配音自检
../../lib/build-vertical.sh --project . --out hello-nosub.mp4
/usr/bin/python3 ../../lib/gen-subs.py --project .  # 字幕 PNG + manifest
../../lib/burn-subs.sh hello-nosub.mp4 hello-v1.mp4 --manifest subs/manifest.tsv
../../lib/verify-output.sh hello-v1.mp4 --expect-w 1080 --expect-h 1920 --fps 30
```

`tests/validate.sh` 会自动跑上面全套。

## 这个样例覆盖了什么

| 环节 | 覆盖点 |
|---|---|
| `clips.json` | 单一事实源；第一句是具体钩子（人物+动作+次数） |
| `shots.tsv` | 三种编码器 `celeb` / `card` / `full` 各一拍 |
| audio-driven | 每拍时长 = 配音时长 + GAP，视频时长由音频决定 |
| 音轨拼接 | `apad` + `atrim` 防逐拍漂移 |
| 字幕 | PIL overlay 路线（本机 ffmpeg 无 libass） |
| 自检 | 分辨率 / 时长 / 音轨 / faststart 全部机械校验 |

## 换成真东西

1. `clips.json` 改成真口播稿（单句 ≤30 字，写「他/她」不写「ta」）
2. `lib/gen-voice.mjs` 生成真配音覆盖 `audio/`
3. `footage/` 换成真实切片（`skills/real-clip-mashup/`）或产品录屏（`skills/product-demo/`）
4. `shots.tsv` 里的起始秒重新量（`ffmpeg -ss N -i src.mp4 -frames:v 1 /tmp/probe.png` 看图取点）
