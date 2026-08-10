---
name: tts-voiceover
description: 用 MiniMax T2A v2 生成口播配音——音色选择、语速、克隆音、读音坑、计费区域坑、失败码速查。配音是整条管线的时间轴来源，必须先做。触发词：配音、口播、TTS、语音合成、MiniMax、音色、克隆音、旁白。
---

# tts-voiceover — 配音

**配音先做，而且配音时长决定后面一切。** 视频每一拍多长 = 这句配音多长 + GAP。
反过来做（先定画面长度再让配音去凑）必然出现死寂空档。

---

## 一、API

MiniMax T2A v2。**区域分两套，账户/余额/key 全独立**：

| 区域 | base |
|---|---|
| 国际 | `https://api.minimax.io/v1` |
| 国内 | `https://api.minimaxi.com/v1` |

key 打错区域 → `2049 invalid api key`。脚本默认国际区，用 `MINIMAX_API_BASE` 覆盖。

请求体（`POST {base}/t2a_v2`，`Authorization: Bearer <key>`）：

```json
{
  "model": "speech-2.5-hd-preview",
  "text": "这一句口播的文字",
  "voice_setting": { "voice_id": "presenter_male", "speed": 1.28, "vol": 1.0, "pitch": 0 },
  "audio_setting": { "sample_rate": 32000, "bitrate": 128000, "format": "mp3", "channel": 1 },
  "language_boost": "Chinese",
  "subtitle_enable": false
}
```

返回 `data.audio` 是 **hex 字符串**，要 `Buffer.from(hex,'hex')` 再写文件。
返回的 SRT 每个 clip 只有 1 段，**不是逐字时间戳**，做不了逐句字幕——字幕自己算（见 `skills/subtitles/`）。

现成脚本：`lib/gen-voice.mjs`

```bash
# 1) 先出音色候选给人类挑（agent 听不到成品音，必须让人拍板）
MINIMAX_API_KEY=... node lib/gen-voice.mjs --sample \
    --text "他三天没回。你点开他的朋友圈，第十七次。" --out audio/samples/

# 2) 定了音色再全量
MINIMAX_API_KEY=... node lib/gen-voice.mjs \
    --clips clips.json --out audio/ --voice presenter_male --speed 1.28
```

---

## 二、音色按题材选

| 题材 | voice_id | 倍速 |
|---|---|---|
| 知识 / 严肃 / 揭秘 / 纪录片感 | `presenter_male`（男主播） | 1.28–1.32 |
| 年轻 / 情感 / 约会 / 共鸣 | `female-tianmei`（甜美年轻） | 1.24 |
| 营销号轻快 | `female-shaonv`（少女） | 1.24–1.28 |
| 第一人称本人叙述 | 克隆音 voice_id | 1.10–1.18 |

**慎用**：`female-yujie`（御姐）、`presenter_female`（女主播）——被评价为「不够年轻 / 发飘」。
**明确否过**：严肃/揭秘题材配营销号女声。

克隆音的 voice_id 是账号私有的，不在这个 repo 里 —— 见 `SECRETS-CHECKLIST.md`。

语速还不够快时可以叠后处理：`ffmpeg -i in.mp3 -af atempo=1.05 out.mp3`
（TTS 1.18 + atempo 1.05 ≈ 有效 1.24×）。`atempo` 单次范围 0.5–2.0，超出要串联。

---

## 三、文本怎么写（决定成品听感）

- **写 `他` / `她`，不写 `ta`** —— 拉丁字母会被念成「T-A」，听起来像故障。
  屏幕字幕为设计需要写 "TA" 可以，**说的那份必须是汉字**。
- **英文品牌名直接写英文**，比拼音标注读得准。
- **年份写阿拉伯数字**（`2021`），正常速度下念得自然。
- **别加显式停顿标记**（`<#x#>` 之类），用自然标点控制节奏。
- 停顿太多 → 长「。」改「，」少一拍；「——」也会触发停顿，能省则省。
- `silenceremove` 滤镜**没用** —— 这类 TTS 输出里没有真正的静音段可删。
- 单句**理想** ≤ 30 字，但这不是硬上限 —— 真实交付稿里有 43 / 61 / 88 字的句子，
  照样正常出片。长句只要**句内标点够**（TTS 靠标点换气），就没问题。
  真正卡人的是「这一拍要占多长画面」，见 `skills/topic-and-script/`。

---

## 四、生成后必须自检

TTS 失败会写出 0 字节或极短文件，concat 时悄悄少一拍，成品音画全错位。

```bash
lib/verify-audio.sh audio/ clips.json
```

它检查：文件存在且非空 / 能被 ffprobe 解析 / 时长在合理区间 / `max_volume` 不是静音 /
字数÷时长 在 2.5–8 字每秒（偏离说明语速参数错了或文本没对上）。

---

## 五、报错速查

| 现象 | 含义 | 修法 |
|---|---|---|
| `1008 insufficient balance` | 余额不足 | **TTS 扣的是 pay-as-you-go 余额，不是 credits**。credits 池（订阅/赠送）常标注「Language models only」，充到那儿 TTS 照样报错。要充 pay-as-you-go。 |
| `2042 no access to voice_id` | 这个账号没有该克隆音权限 | 换成拥有克隆音的那个 key |
| `2049 invalid api key` | key 和区域对不上 | 国际 key 配 `api.minimax.io`，国内 key 配 `api.minimaxi.com` |
| 返回 200 但文件是 0 字节 | `data.audio` 为空 | 打印 `base_resp` 看真实错误码，别只看 HTTP 状态 |
| 中文被读成英文腔 | 缺 `language_boost` | 加 `"language_boost": "Chinese"` |

**排查顺序**：先看 `base_resp.status_code`（不是 HTTP code）→ 对区域 → 对余额池 → 对 voice 权限。

---

## 六、留给人类的审核点

**agent 听不到成品音**，判断不了「够不够有情绪」。所以：

1. 每条片子先生成 **3 个音色候选**（同一句话），打包给人类挑。
2. 全量生成后，把**总时长**和**每句时长**列出来给人类看一眼再往下走。
3. 别自己拍板「这个音色挺好」。

---

## 七、密钥

`MINIMAX_API_KEY` 之类**不进 repo、不进 commit、不回显**。
从环境变量读，见 `SECRETS-CHECKLIST.md`。
