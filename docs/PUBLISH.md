# 怎么把这两个仓推上去、把 PR 开出来

你只需要做一件事：**建一个 classic PAT 贴给我**。剩下的我用 `scripts/publish.py` 一条命令跑完。

---

## 一、建 token（2 分钟）

1. 浏览器打开 <https://github.com/settings/tokens>

   （路径：右上角头像 → **Settings** → 左侧最下 **Developer settings** → **Personal access tokens** → **Tokens (classic)**）

2. 点右上 **Generate new token** → 选 **Generate new token (classic)**

   ⚠️ 不要选 "Fine-grained tokens"。细粒度 token 对"fork 别人的公开仓库"限制很多，这一步会失败。

3. 填：

   | 字段 | 填什么 |
   |---|---|
   | Note | `workbuddy-publish` |
   | Expiration | **7 days**（够用，过期自动失效） |
   | Select scopes | 勾 **`repo`**（整块，会连带下面全勾上）+ 勾 **`workflow`** |

   - `repo`：建仓、推代码、fork、开 PR
   - `workflow`：推 `.github/workflows/` 里的 CI 文件需要它，不勾会被 GitHub 拒收

4. 页面底部 **Generate token** → 复制 `ghp_` 开头那一整串

   ⚠️ 这串只显示一次，关掉页面就看不到了（看不到就重新生成一个）。

5. **直接贴在对话里发我**，一行就够：

   ```
   ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```

## 二、我拿到之后会跑什么

```bash
GITHUB_TOKEN=<你的token> python scripts/publish.py --user Richard-Yhn
```

脚本做的事（每一步都幂等，失败可以重跑）：

| 步骤 | 动作 | 产物 |
|---|---|---|
| 1 | `GET /user` 校验 token，确认身份是 Richard-Yhn | — |
| 2 | 建 `Richard-Yhn/deepseek-bot-ios`（已存在就跳过），推本地 `main` | iOS 仓 |
| 3 | fork `Fei2411/DeepSeek-Bot` 到你的账号（已存在就跳过） | fork |
| 4 | 把 `feat/room-log` 推到 fork | 分支 |
| 5 | 对上游 `dev` 开 PR（已存在就打印链接） | PR |

PR 标题：`feat: add a room-log endpoint so a client can read a group chat`
PR 正文：`docs/upstream-pr-body.md`（英文，和上游仓库语言一致）

推完 iOS 仓，CI 会自动开始编译，产出未签名 `.ipa` 在 Actions → Artifacts。

## 三、你要留意的一件小事

上游的 `CONTRIBUTING.md` 要求从最新的 **`dev`** 分支起新分支，而我这份补丁是在 `main`（`ae63b45`）上做的。如果 `dev` 比 `main` 领先很多，PR 页面可能显示冲突。真冲突了我再 `rebase` 到 `dev` 上重推一次，补丁本身只有 3 个文件、改动很浅，不难。

## 四、用完请把它删掉

token 贴在对话里，就等于留在了会话记录中。

- 7 天后它自动过期（你选的）
- 想立刻失效：回到 <https://github.com/settings/tokens> → 找到 `workbuddy-publish` → **Delete**

它现在能做的事：读写你账号下**所有**仓库。所以别延长有效期、别复用，用完就删。

## 五、如果你不想给 token

那就在自己电脑上跑两条命令（需要装 Git，Windows 用 Git Bash）：

```bash
# iOS 仓：先在 GitHub 网页上建一个空仓库 deepseek-bot-ios（不要勾 README）
cd deepseek-bot-ios
git remote add origin https://github.com/Richard-Yhn/deepseek-bot-ios.git
git push -u origin main
```

PR 那一步更省事的办法：在 GitHub 网页上点开 `Fei2411/DeepSeek-Bot` → 右上 **Fork** → 回到 `_src/ds-bot`：

```bash
cd _src/ds-bot
git remote add fork https://github.com/Richard-Yhn/DeepSeek-Bot.git
git push fork feat/room-log
```

然后浏览器打开 `https://github.com/Fei2411/DeepSeek-Bot/compare/dev...Richard-Yhn:feat/room-log?expand=1`，
标题用上面那句，正文把 `docs/upstream-pr-body.md` 的内容粘进去，点 **Create pull request**。
