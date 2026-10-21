# 客户端通道

宿主：DeepSeek Harness（`dsh web`）。业务插件：`ds-bot`。本 App 只用官方 Web 界面也在用的那一条路由：

```
POST http://<host>:<port>/api/bot
Content-Type: application/json
Cookie: <dsh 登录 cookie>

{ "endpoint": "state", "payload": { … } }
```

应答二选一：

```json
{ "ok": true,  "value": … }
{ "ok": false, "error": { "code": "bot/invalid", "message": "Nothing to send", "details": {} } }
```

`code` 里 `bot/refused`、`bot/invalid`、`bot/read-only`、`bot/not-found`、`bot/browser-off` 是**给用户看的拒绝**（`ds-bot/src/client/api.js` 的 `REFUSALS`），其它一律是可展示的错误。本 App 把 `message` 原样显示。

## 认证

`dsh web` 启动时打印：

```
dsh web: http://127.0.0.1:3080/?token=… (LAN: http://172.x.x.x:3080/?token=…)
```

用 `GET` 打开这个 URL，宿主会 `Set-Cookie` 一个**签名 cookie，30 天有效，绑定该 authority**。之后所有 `/api/bot` 带 cookie 即可，token 只出现一次。

本 App 的流程：

1. `GET <origin>/?token=…` （只为拿 cookie，响应体丢弃）
2. `POST /api/bot {"endpoint":"state"}` —— 既当握手也当校验
3. cookie 由 `HTTPCookieStorage.shared` 保存；「完整界面」用同一个带 token 的 URL 加载，自己再拿一份 cookie

## 用到的端点

| endpoint | 载荷 | 回值（本 App 读取的部分） | 用途 |
|---|---|---|---|
| `state` | `{ "locale": "zh-CN" }` | `revision, mainBotIds, bots[], rooms[], models[], prefs, readOnly, work{bots, approvals[], turns}` | 团队快照 / 轮询 |
| `chat` | `{ "botId": "<id>", "cursor": { "part": n, "beforeSeq": m }? }` | `{ sessionId, items[], cursor }` | 单个 Bot 的对话 |
| `send` | `{ "sessionId": "<会话 id>", "text": "<文本>" }` | `true` | 发一句话 |
| `approval-answer` | `{ "id": "<审批 id>", "choice": "allow" \| "reject" }` | `true` | 群聊工具审批 |

`choice` 只有两个字面值，映射见 `ds-bot/src/host/approvals.js`：

```js
const OUTCOMES = { allow: 'allowed-once', reject: 'rejected' }
```

传别的值会被拒：`bot/invalid: Choose allow or reject`。

## 数据结构要点

### `state` 的 Bot

```js
{ id, name, role, color, avatar, model, effort,
  sessionId,      // 当前这段自己的会话；send 用它
  parts: [ … ],   // 更早的分段
  waiting: true } // 还没选模型，压着开场白
```

`mainBotIds[0]` 是侧栏的那块主 Bot 磁贴。

### `state` 的只读

`readOnly` 非 null 表示**另一个 dsh 宿主正占着这支团队**，此时写操作一律 `bot/read-only`。本 App 会禁掉输入条并在标题栏标「只读」。

### `state` 的审批

```js
{ id, sessionId, botId, roomId?, tool, reason,
  detail: { text?, code? }, at: <epoch ms>, answerable }
```

`approvals` 只由**群聊里隐藏的成员会话**产生——Bot 自己的对话用的是 DSH 原生审批卡，不进这里。

### `chat` 的消息项

由 `displayItems()`（`ds-bot/src/host/parts.js`）生成，一个文本块一条：

```js
{ kind: 'bot',    text, time }
{ kind: 'user',   text, images?, time }
{ kind: 'answer', questions? | views? | text?, answers?, time }
{ kind: 'event',  role: 'request'|'reply'|'report'|'stopped', name?, botId?, roomId?, time }
{ kind: 'divider', time }          // 分段开始
```

`time` 是事件时间，宿主写 epoch 毫秒，本 App 也接受秒和 ISO 8601。

## 管理与派活

| endpoint | 载荷 | 说明 |
|---|---|---|
| `create-bot` | `{ name, role?, color?, brief?, instructions?, model?, effort?, workDir?, pickModel? }` | `name` ≤40 且唯一；`role` ≤24；`color` 是**名字**不是 hex；`pickModel: true` 表示先建、模型后选 |
| `update-bot` | `{ id, name?, role?, color?, brief?, instructions?, model?, effort?, workDir? }` | `model: null` / `effort: null` 是**清空**，不是"不改" |
| `delete-bot` | `{ id }` | 回新的团队视图 |
| `set-main` | `{ id, main: true, primary?: bool }` | `primary` 表示替换原来的主 Bot |
| `create-room` | `{ name, members: [botId…], admin?, greet? }` | `greet: true` 让宿主建完就跑开场轮 |
| `delete-room` | `{ id }` | |
| `efforts` | `{ ref }` | 回 `{ efforts: [{id,name,description?}], defaultEffort? }`；没有思考档位时 `{ efforts: [] }` |
| `folders` | `{}` | 回 `{ team, picker, folders: [{path,title}] }` —— 团队已在用的目录，不是文件浏览器 |

**派活不是端点**，是 N 次 `send`。每个 Bot 是独立的 root Session，宿主并行跑各自的 turn：

```json
{ "endpoint": "send", "payload": { "sessionId": "<bot 的当前会话>", "text": "同一件事 + 你这一份的重点" } }
```

## 供应商与自定义模型

| endpoint | 载荷 | 回值 |
|---|---|---|
| `providers` | `{}` | `{ available, providers: [{id,name,models,key:{configured,writable}\|null,removable,custom,error?}], addable, protocols }` |
| `provider-key` | `{ provider, value }`（`value: null` 清除） | 新的供应商视图 |
| `provider-add` | 见下 | 新的供应商视图 |
| `provider-models` | `{ baseURL, api?, key? }` 或 `{ provider }` | `[{ id, name?, contextWindow?, maxTokens? }]`，**不存 key** |
| `provider-remove` | `{ provider }` | 只能删用户自己加的 |

协议只能是 `providers.protocols` 给的那三个：
`openai-completions` / `openai-responses` / `anthropic-messages`。

接一个自建网关：

```json
{
  "endpoint": "provider-add",
  "payload": {
    "provider": "my-router",
    "custom": true,
    "name": "我的中转",
    "api": "openai-completions",
    "baseURL": "https://api.example.com/v1",
    "models": [{ "id": "llama-3.1-70b" }],
    "key": "sk-…"
  }
}
```

之后这个供应商的模型就在 `state.models` 里，ref 是 `my-router/llama-3.1-70b`，任何 Bot 都能选。`provider` 的 id 规则是 `^[a-z][a-z0-9]*(?:-[a-z0-9]+)*$`。

密钥只写不读：`key.configured` 是宿主愿意说的全部，`describe()` 从此只会回答"有没有配"。

## 增量同步

`state` 带 `since` 时，宿主在没变化的情况下走短路：

```js
if (body.since === state.revision && …) return ok({ revision, unchanged: true, ...live() })
```

也就是回一个**没有 `bots` / `rooms`** 的应答，只有 `live()`。所以客户端必须：

- `unchanged === true` → 只合并 `work` / `questions` / `views`，团队本体保持原样
- 否则整份替换，并记下新的 `revision`

App 按这个规则做（`TeamModel.refresh`），并把节奏调到 1.2 / 1.5 / 4 秒三档。

## 直连模型（不走宿主）

「直连模型」页完全绕开 `/api/bot`，直接对任意 OpenAI 兼容端点做流式请求：

```
POST <baseURL>/chat/completions
Authorization: Bearer <key>
{ "model": "…", "messages": [{ "role": "user", "content": "…" }], "stream": true }
```

解析 `data:` 行直到 `[DONE]`，取 `choices[0].delta.content` 逐字追加。这条路上的 key 只存在手机里。

## 容错约定

宿主每次发版都可能加字段，所以 `Sources/Models/Values.swift` 里：

- `Ignored` —— 任何 JSON 值都能解，用来吞掉本 App 不渲染的结构
- `FlexibleList` —— 数组或按 id 的对象都当列表，解不动就退化成空列表，绝不抛
- `DSBTime` —— 毫秒 / 秒 / ISO 三种都认，认不出就 nil

目标是：**宿主加字段不会让 App 打不开团队**。
