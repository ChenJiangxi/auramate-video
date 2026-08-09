# SECRETS-CHECKLIST — 需要人类传入的凭据

**这个 repo 里没有任何真实密钥，也永远不会有。**
下面列出跑通全部管线需要哪些值、从哪来、缺了会卡在哪一步。
人类把值作为 prompt 传给 agent，或写进 agent 自己的密钥管理器 / 环境变量。

Agent 收到这些值之后：**绝不回显、绝不写进文件、绝不写进 commit、绝不写进日志。**
只以环境变量形式注入到子进程。用完提醒人类轮换。

---

## 必须（不给就做不了片）

### 1. `MINIMAX_API_KEY` — 配音

- **用途**：MiniMax T2A v2 生成口播配音。配音时长驱动整条时间轴，没有它整个管线停在第 4 步。
- **注意区域**：国际区 key 配 `https://api.minimax.io/v1`；国内区 key 配 `https://api.minimaxi.com/v1`。
  配错报 `2049 invalid api key`。用 `MINIMAX_API_BASE` 指定。
- **注意余额**：TTS 扣的是 **pay-as-you-go 余额**，不是 credits 池。
  credits（订阅/赠送）常标注「Language models only」，充到那儿 TTS 照样报 `1008`。
- **用法**：

  ```bash
  MINIMAX_API_KEY='<值>' node lib/gen-voice.mjs --clips clips.json --out audio/ --voice presenter_male
  ```

### 2. 克隆音 `voice_id` — 只有需要「本人声音」时

- **用途**：第一人称叙述的片子要用委托人自己的克隆音。
- **形态**：一个字符串 ID（不是密钥，但属于账号私有信息，同样不进 repo）。
- **注意**：克隆音**绑定在特定账号上**。换一个 key 去调可能报 `2042 no access to voice_id`。
- **不需要它的场景**：用系统音色（`presenter_male` / `female-tianmei` / `female-shaonv`）就不用给。

---

## 按需（对应功能用不上就不用给）

### 3. 产品站登录凭据 — 只有要录自家产品界面时

| 变量 | 说明 |
|---|---|
| `DEMO_SITE_URL` | 产品站地址。**必须是真实域名**，别录成撞名的站 |
| `DEMO_LOGIN_EMAIL` | 测试账号 |
| `DEMO_LOGIN_PW` | 测试账号密码（**只走环境变量，不进命令行 argv** —— argv 会泄露到 `ps`） |

用法：

```bash
DEMO_LOGIN_PW='<值>' node lib/rec-page.js \
  --url "$DEMO_SITE_URL/app" --login-url "$DEMO_SITE_URL/login" \
  --email "$DEMO_LOGIN_EMAIL" --pw-env DEMO_LOGIN_PW \
  --out footage/rec/demo.webm --mobile
```

> 建议用**测试账号**，不要用主账号。录屏会把账号里的真实内容拍进去。

### 4. 图像生成 API key — 只有需要生成封面背景图时

- 用不着也行：封面背景优先用**成片抽帧**（一致性更好，也更真实）。

### 5. `git` push 权限 — 只有需要 agent 自己推 repo 时

- 本机 ssh key 或 token。
- **边界要人类明确划**：允许推哪些 repo、不允许碰哪些。agent 不要越界。

---

## 不需要给的

- `yt-dlp` 扒公开视频 —— 不需要 key。
- `ffmpeg` / `Pillow` / `playwright` —— 本地工具，不需要 key。
- 平台发布账号 —— 这套 skill 只做到**交付**，不代发。发布是人类的动作。

---

## 交付给 agent 的推荐格式

人类可以直接把下面这段填好发给 agent（**发完记得删掉聊天里的明文**）：

```
MINIMAX_API_KEY=<值>
MINIMAX_API_BASE=https://api.minimax.io/v1      # 国内区改成 https://api.minimaxi.com/v1
CLONE_VOICE_ID=<值>                              # 没有就留空，用系统音色
DEMO_SITE_URL=<值>                               # 不录产品就留空
DEMO_LOGIN_EMAIL=<值>
DEMO_LOGIN_PW=<值>
```

Agent 收到后应当：

1. 立即写进自己的密钥管理器 / 环境变量，**不落盘成明文文件**；
2. 回复里只确认「已收到 N 个值」，**不回显任何一个值**；
3. 提醒人类删除聊天里的明文消息，并在项目结束后轮换。

---

## 自检

跑一下就知道当前环境缺什么：

```bash
./tests/check-deps.sh          # 工具链
env | grep -c MINIMAX_API_KEY  # 1 = 已注入（不要 echo 值本身）
```

`tests/validate.sh` 里带了一个**泄密扫描**，会拦住误写进 repo 的 key 形态字符串。
每次 push 前它都会跑。
