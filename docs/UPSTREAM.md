# 与 Fei2411/DeepSeek-Bot 的关系

**不是 fork，也不是它的分支。** 两个仓库解决的是不同层的问题：

| | `Fei2411/DeepSeek-Bot`（上游） | 本仓库 `deepseek-bot-ios` |
|---|---|---|
| 是什么 | DSH 插件 `ds-bot` + Electron 桌面壳 `app/` | iOS 客户端 |
| 语言 | JavaScript / Node / Electron | Swift / SwiftUI |
| 跑在哪 | 你的电脑或 NAS（宿主） | iPhone |
| 拥有数据 | Bot 团队、会话、工具、文件、记忆、定时任务 | 只有一份缓存和登录 cookie |
| 构建产物 | `win-x64.exe`、macOS `.zip`（Electron） | 未签名 `.ipa`（Xcode / CI） |
| 协议 | 提供 `POST /api/bot` | 消费 `POST /api/bot` |

所以"打包 Windows 和 macOS"在上游那边（Electron 壳），"打包 iOS"在这边（SwiftUI）。
两边共享的只有那一套 `/api/bot` 端点和数据结构。

## 本仓库对上游的唯一改动请求

`patches/room-log.patch` —— 给 `/api/bot` 加一个 `room-log` 端点。

为什么加：`state` 里每个房间的 `log` 被 `view()` 解构丢弃，只留最后一句 `preview`：

```js
// ds-bot/src/host/channel.js — view()
rooms: Object.values(state.rooms).map(({ log, seen, lateRounds, sessions, segments, ...room }) => {
  const last = (log ?? []).filter(line => line.kind === undefined).at(-1)
  return { ...room, parts, ...(last ? { preview: … } : {}) }
})
```

而 `chat` / `earlier` 都要求 `botOf(sessionId)`，房间 id 永远不满足。结果是：**任何不是
DSH 自带 Web 窗口的客户端，都读不到群聊记录**——iOS、第三方面板、命令行工具都一样。

补丁只做加法：新端点 + 纯函数 + 9 个单测，不动任何现有返回值和行为。

## 这个补丁做了什么

| 文件 | 改动 |
|---|---|
| `ds-bot/src/host/room-log.js` | 新增。纯分页函数 `roomLogPage(room, cursor)`，不依赖 DSH |
| `ds-bot/src/host/channel.js` | 加 `case 'room-log'`（4 行）、import、`room-log` 进 `READS` 集合 |
| `ds-bot/test/room-log.test.js` | 新增。9 个用例，`node --test` 直接跑，不需要 `dev/harness/` |

请求 / 应答：

```json
{ "endpoint": "room-log", "payload": { "roomId": "…", "before": 41, "limit": 20 } }

{ "ok": true, "value": {
    "seq": 58, "kept": 60, "limit": 20,
    "lines": [
      { "seq": 42, "who": "阿鲸", "botId": "…", "text": "…" },
      { "seq": 43, "who": "User", "text": "…", "length": 9000 }
    ],
    "cursor": { "before": 42 }
} }
```

- `before` 是调用方已持有的最旧一条的 `seq`；返回比它更旧的最后一页
- `cursor: null` 表示到头了，或者宿主已经把更早的丢了（只留 `ROOM_LOG_KEPT = 60`）
- `length` 只在文本被截断时出现，全文仍可用 `file-text` 取
- 未知 `roomId` → `bot/not-found`，不抛异常
- 在 `READS` 里，所以"只读宿主"也答得出来

## 验证过什么

```bash
node --check ds-bot/src/host/room-log.js     # OK
node --check ds-bot/src/host/channel.js      # OK
node --test  ds-bot/test/room-log.test.js    # 9 pass / 0 fail
```

**没验证**：没跑上游的 `npm test`（需要 `dev/harness/` 里的 DSH 包）和 smoke test（需要 mock 模型与 DSH 检出）。这两个要在提交 PR 前补跑，见 `CONTRIBUTING.md`。

## 怎么把这个 PR 发出去

补丁在 `patches/room-log.patch`，也可以直接用 `git am`：

```bash
# 1. 在你自己的 fork 上建分支（CONTRIBUTING 要求从最新 dev 起）
git clone https://github.com/<你的账号>/DeepSeek-Bot.git
cd DeepSeek-Bot
git remote add upstream https://github.com/Fei2411/DeepSeek-Bot.git
git fetch upstream dev && git switch -c feat/room-log upstream/dev

# 2. 应用补丁
git am /path/to/patches/room-log.patch

# 3. 跑他们要求的检查
cd ds-bot && npm install --prefix dev/harness --legacy-peer-deps=false --no-package-lock --no-fund --no-audit
npm test
npm run lint
cd .. && ./dev/check.sh        # smoke test，也可以先跳过

# 4. 推上去开 PR（base 选 dev）
git push -u origin feat/room-log
```

PR 标题：

```
feat: add a room-log endpoint so a client can read a group chat
```

PR 正文（可直接粘，英文与上游一致）：

```markdown
## What

`room-log { roomId, before?, limit? }` returns one page of `room.log` over
`POST /api/bot`: newest page first, cursor by `seq`, `kept` reporting how many lines
the host still holds.

## Why

`state` carries only the last line of each room as `preview` — `view()` destructures
`log` out of every room — and `chat` / `earlier` both gate on `botOf(sessionId)`,
which a room id never satisfies. So a client that is not this window has no way to
read a group chat: an iPhone client, a desktop panel, a CLI, all of them.
This adds the read side only; writing already works through `send` with `room.id`.

## How

- `src/host/room-log.js` — pure paging over the array, no DSH imports, so it is
  covered by `test/room-log.test.js` (9 cases) without `dev/harness/`.
- `src/host/channel.js` — one `case`, and `room-log` in `READS` so a reading host
  answers it.
- A cut line keeps the head it stored plus `length`; `file-text` still fetches the
  whole text, so nothing new is needed for long posts.

## Compatibility

Additive. No existing endpoint, payload or return value changes. `room-log` follows
`room-progress` in shape and error codes (`bot/not-found` for an unknown room).

## Tests

```
node --test ds-bot/test/room-log.test.js
# 9 pass / 0 fail
```

`npm test` and `npm run lint` still need a run with `dev/harness/` installed.
```

## 这个补丁落地前，App 怎么办

`RoomDetailView` 先探测：第一次调 `room-log` 若回 `Unknown endpoint room-log`，就退回到
"最后一句 + 说明"，并继续提供发消息、实时进度、停轮、审批。补丁一上线，同一页自动变成
完整群聊记录，**App 不需要再改**。
