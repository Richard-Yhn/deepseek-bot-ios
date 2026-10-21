# DeepSeek Bot for iOS

把 **DeepSeek-Bot** 的团队搬到 iPhone 上。底层是 DeepSeek Harness（dsh），协议和数据结构照搬 [Fei2411/DeepSeek-Bot](https://github.com/Fei2411/DeepSeek-Bot)，客户端骨架取自 [Pedroshakoor/grok-build-ios](https://github.com/Pedroshakoor/grok-build-ios)。

**手机既是遥控器，也是一份算力。** 它盯着桌面端的团队实时同步、能管理团队；也能绕开宿主，直接接任意 OpenAI 兼容接口自己算。

---

## 三件事

### 1. 接桌面端，实时同步

```
        iPhone（这个仓库）                   你的电脑 / NAS
┌────────────────────────────┐      ┌──────────────────────────────────┐
│ SwiftUI                      │      │ dsh web（DeepSeek Harness）      │
│  · Bot 团队  ◆/◇ · 模型 · 任务  │ HTTP │  └─ ds-bot 插件                  │
│  · 单 Bot 对话 + 输入条        │─────▶│      · 长期活着的 Bot 团队         │
│  · 派活 · 群聊 · 供应商         │ POST │      · Bot 间派活、群聊、审批      │
│  · 完整界面（WKWebView 兜底）   │      │      · 工具、记忆、定时任务、文件   │
└────────────────────────────┘      └──────────────────────────────────┘
        │  另有一路：直连模型（不经宿主）
        └─────────────────────────────▶ https://api.deepseek.com/v1 等
```

同步不是三秒一刷的假实时：

- 每轮只带 `since: <revision>`，宿主没变就回一个 `unchanged: true` 加几百字节的 `live()`（谁在跑、谁在等审批、哪一轮几点开始）。
- 节奏自己会变：**对话页 1.2 秒**、**有 Bot 在干活 1.5 秒**、闲时 4 秒。
- 任何写操作（建 Bot、派活、审批）之后立刻 `force` 拉一次全量，不等下一拍。
- 下拉 = 强制全量刷新。

### 2. 每个 Bot 各接一个模型，各领一份任务，同时跑

这是宿主本来的形状，App 只是把它接到手上：

- **每个 Bot 一个模型 ref**（`provider/model`）。模型下拉按供应商分组，自带 DeepSeek 的，也有你自己加的。
- **每个 Bot 一份任务**：`brief`（一句话职责，一直挂在它的提示里）+ `instructions`（长期要求）。
- **同时处理**：宿主里每个 Bot 就是一条独立的 root Session，所以"派活"页勾五个 Bot、各写一句重点，就是五次 `send` —— 五个 turn 在宿主上真并行，不是排队。

### 3. 手机自己也能算

「直连模型」页不走宿主：填 `baseURL` + `model` + `key`，手机直接对本机/云端接口做 SSE 流式对话（`/chat/completions`, `stream: true`）。没网到宿主、宿主没开、在蜂窝上，都能用。

聊出结论后点「交给团队」，挑一个 Bot，这段文本就通过 `send` 进了它的对话 —— 手算的结果回到团队里，而不是烂在手机里一个笔记 App。

---

## 快速开始

### 1. 宿主侧（电脑或 NAS）

```bash
# 桌面版：直接打开 DeepSeek Bot
# 或者命令行：
npx @deepseek-ai/dsh@0.2.1-rc.2 plugin --profile web add ds-bot
npx @deepseek-ai/dsh@0.2.1-rc.2 web
```

启动后打印：

```
dsh web: http://127.0.0.1:3080/?token=… (LAN: http://172.x.x.x:3080/?token=…)
```

把 `127.0.0.1` 换成局域网 IP（LAN 那行直接可用）。这行 token 会换成一个 30 天有效的签名 cookie。

### 2. 手机侧

1. 手机和电脑同一 Wi-Fi。
2. 打开 App，把整条 `http://<局域网IP>:3080/?token=…` 粘进去，点「连接宿主」。
3. 第一次会弹「本地网络」权限，**必须允许**。
4. 连上就是团队列表。右上角「新建」加 Bot，底部一排是 派活 / 群聊 / 供应商 / 直连模型 / 完整界面 / 设置。

### 3. 给 Bot 接自定义模型

1. 底部 →「供应商」→「接一个自定义供应商」。
2. 填：供应商 id（`my-router`）、接口地址（`https://xxx/v1`）、协议（`openai-completions` / `openai-responses` / `anthropic-messages`）、可选 Key、模型 id（一行一个，或点「发现模型」让接口自己报）。
3. 回到团队 →「新建」→ 模型下拉里就多了一组 `我的中转 · 模型名`。

`provider-add` 的 `custom: true` 是宿主认的那条路；密钥只写不读，宿主永远不会把它吐回来。

### 4. 编译 / 拿 IPA

需要 macOS + Xcode（或交给 CI）：

```bash
brew install xcodegen
xcodegen generate
open DeepSeekBot.xcodeproj      # 选开发团队签名，直接跑到手机
```

只要未签名 IPA：

```bash
xcodebuild build -project DeepSeekBot.xcodeproj -scheme DeepSeekBot \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

mkdir -p out/Payload && cp -R build/Build/Products/Release-iphoneos/DeepSeekBot.app out/Payload/
cd out && zip -qry DeepSeekBot-unsigned.ipa Payload
```

### 5. 桌面端（Windows / macOS）

桌面端不是这个仓库的代码，是上游的 Electron 壳。`.github/workflows/desktop.yml` 手动触发后：克隆上游 → 应用 `patches/room-log.patch` → 用上游自己的 `electron-builder.yml` 打包，产出 `.exe` / `.zip`。这样打出来的包和上游发布的一致，只是多了 `room-log`。

```
Actions → desktop → Run workflow
  ref:         main
  apply_patch: true
```

**标为实验**：没在真机上跑过，`npm ci` 与 electron-builder 的下载都依赖当时的 npm 源。

### 6. 装到 iPhone

| 方式 | 需要 | 有效期 |
|---|---|---|
| **Sideloadly / AltStore / SideStore** | 免费 Apple ID 即可 | 7 天，到期重签 |
| Xcode 直接跑（数据线） | 免费 Apple ID | 7 天 |
| TestFlight | 付费开发者账号 | 90 天 |

---

## 原生做了什么，什么交给「完整界面」

原生（`/api/bot`）：

| 能力 | 端点 |
|---|---|
| 团队实时同步 | `state`（`since` 增量） |
| 单个 Bot 对话、往前翻页 | `chat`、`send` |
| 建 / 改 / 删 Bot、设主 Bot | `create-bot`、`update-bot`、`delete-bot`、`set-main` |
| 模型与思考档位 | `models`（来自 `state`）、`efforts` |
| 工作目录 | `folders` |
| 派活（多个 Bot 并行） | 多次 `send` |
| 建 / 删群聊 | `create-room`、`delete-room` |
| 群聊发消息 | `send`（`sessionId: room.id`，房间就是 Session） |
| 群聊实时进度 / 停某一轮 | `room-progress`、`stop-member-work` |
| 群聊工具审批 | `approval-answer` |
| 供应商与自定义模型 | `providers`、`provider-key`、`provider-add`、`provider-models`、`provider-remove` |
| 手机直连模型 | 第三方 `/chat/completions`（SSE） |

交给 WKWebView（底部「完整界面」）—— 手机上用得少，但一个都不能缺：

- 群聊的完整消息流（房间日志不在 `chat` 通道上）、拉人改群
- Bot 的回答卡片、工具调用细节
- 记忆面板、定时任务、能力库、DSH 自身设置
- 卡片式提问的作答（`questions`/`views` 的形状宿主还在演进，原生只提示不猜）

这个分工是故意的：宁可一个按钮跳原版，也不做半真的复刻。

---

## 目录

```
project.yml                  XcodeGen 工程定义（.xcodeproj 是生成物，不入库）
Sources/
  DeepSeekBotApp.swift       入口；cookie 接受策略设为 always
  RootView.swift             屏幕路由 + 错误提示条
  TeamModel.swift            唯一状态对象：增量同步、管理动作、派活、供应商
  Net/
    DSBClient.swift          POST /api/bot，信封解析，token→cookie 握手
    DirectModelClient.swift  手机直连模型：OpenAI 兼容 SSE
    HostAddress.swift        粘贴地址的解析
    DSBError.swift           宿主拒绝的原话直传
  Models/
    TeamView.swift           bots / rooms / work.approvals / models + 按供应商分组
    ChatPage.swift           bot|user|answer|event|divider + 稳定行身份
    BotDraft.swift           建/改 Bot 的载荷；派活目标
    Provider.swift           供应商、模型发现、思考档位、工作目录
    DirectChat.swift         直连模型的配置与本地会话
    Values.swift             Ignored / FlexibleList / DSBTime（容错解码）
    Chrome.swift             AppScreen、ConnectionPhase、审批选项、设置
  Views/
    OnboardingView.swift     连接页
    TeamListView.swift       团队列表 + 底部动作条
    BotChatView.swift        对话 + PromptBar
    ManageBotView.swift      新建 / 编辑 Bot（模型 · 任务 · 目录 · 删除 · 设为主）
    DispatchView.swift       派活：一件事，多个 Bot 各领一份
    CreateRoomView.swift     建群
    RoomListView.swift       群聊列表 + 审批
    RoomDetailView.swift     单群：记录（有补丁时）/ 发消息 / 谁在说 / 停轮
    ProvidersView.swift      供应商 · 自定义模型 · 密钥 · 发现模型
    DirectChatView.swift     手机直连模型 + 交给团队
    SettingsView.swift       连接、外观、上游
    WebHostView.swift        完整界面
  Ported/                    取自 grok-build-ios 的文件（见 NOTICE）
Tests/DSBCoreTests.swift     地址解析、容错解码、消息行身份
patches/room-log.patch       给宿主加的 room-log 端点（含 9 个单测）
docs/PROTOCOL.md             用到的端点与载荷
docs/UPSTREAM.md             与上游的关系、补丁内容、怎么开 PR
```

## CI

`.github/workflows/ios.yml` 在 `macos-15` 上：装 XcodeGen → 生成工程 → 模拟器跑单测 → 编译未签名设备包 → 打 `.ipa` 传 artifact。发 Release 时自动附到 Release 页。

## 已知限制

- **同一 Wi-Fi 才能连宿主**。外网要自己挂反向代理（宿主有 Host 信任围栏和登录 cookie，别裸奔）。想脱离局域网，就用「直连模型」那一路。
- **群聊记录要靠一个上游补丁**。发消息、实时进度、停轮、审批都是原生的；完整记录需要宿主带 `room-log` 端点——这就是 `patches/room-log.patch` 干的事（新端点 + 9 个单测，纯加法）。宿主没打补丁时，这一页退回到"最后一句 + 说明"，其余功能不受影响；打上之后同一个页面自动变成完整群聊，**App 不用改**。详见 [docs/UPSTREAM.md](docs/UPSTREAM.md)。
- 卡片式提问只提示「在等你回答」，作答仍需完整界面。
- Bot 浏览器读取（`browser-wait`）是桌面窗口的长轮询，手机不做。
- token 与直连模型的 key 都存在 App 沙盒的 UserDefaults 里；等于把宿主登录凭据和 API key 放在这台手机上。

## 许可

Apache-2.0。上游归属见 `NOTICE`。
