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

---

## 实际结果（2026-10-22 01:10）

| 步骤 | 结果 | 链接 |
|---|---|---|
| 建 iOS 仓 + 推 main | ✅ | https://github.com/Richard-Yhn/deepseek-bot-ios |
| iOS CI 首次编译 | ✅ 通过（第 2 次运行） | https://github.com/Richard-Yhn/deepseek-bot-ios/actions/runs/39640765164 |
| 产物 | ✅ `DeepSeekBot-unsigned.ipa` 825 KB | 同上，页面底部 Artifacts |
| fork 上游 | ✅ | https://github.com/Richard-Yhn/DeepSeek-Bot |
| 推 `feat/room-log` | ✅ | https://github.com/Richard-Yhn/DeepSeek-Bot/tree/feat/room-log |
| 对上游开 PR | ❌ API 返回 404 | 需网页点一下（见下） |

### 第一次 CI 失败的原因

```
Sources/Models/Provider.swift:126:8: error: type 'FolderOption' does not conform to protocol 'Identifiable'
```

`FolderOption` 只写了 `uid` 没写 `id`。改成 `id` 后第 2 次运行全绿：
XcodeGen 生成工程 → 模拟器单测 → 编译设备包 → 打成 IPA → 上传 artifact。

### 为什么 PR 那步 404

- token 的 scope 是 `repo, workflow`，没问题
- 同样的 `POST /pulls` 在**你自己的 fork 里**能成功（当时建了测试 PR #1 又关掉了）
- `compare/main...Richard-Yhn:feat/room-log` 也能正常解析（ahead 1 / 3 个文件）

所以缺的不是代码或分支，而是"对别人的仓库开 PR"这一步的账号权限。GitHub 在账号受限时
只会回一个含糊的 404，网页才会说真实原因（最常见：邮箱未验证）。

**点这个链接就能开**（页面若拒绝，会写明原因）：

https://github.com/Fei2411/DeepSeek-Bot/compare/main...Richard-Yhn:feat/room-log?expand=1

### base 为什么是 main 而不是 dev

`compare` 显示：对 `dev` 是 **ahead 8**，对 `main` 是 **ahead 1**。也就是说上游 `dev`
比 `main` 旧 7 个提交，对着 `dev` 开 PR 会把这 7 个无关提交一起带进 diff。
所以 PR 指向 `main`，正文里也写明了这一点，维护者想改回 `dev` 一键 retarget 即可。
