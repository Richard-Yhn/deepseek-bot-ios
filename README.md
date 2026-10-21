# DeepSeek Bot for iOS

把 **DeepSeek-Bot** 的团队搬到 iPhone 上。底层是 DeepSeek Harness（dsh），协议和数据结构照搬 [Fei2411/DeepSeek-Bot](https://github.com/Fei2411/DeepSeek-Bot)，客户端骨架取自 [Pedroshakoor/grok-build-ios](https://github.com/Pedroshakoor/grok-build-ios)。

手机是遥控器，不是算力：Bot 团队、会话、工具、文件全留在你自己的机器上。

---

## 它怎么工作

```
        iPhone（这个仓库）                   你的电脑 / NAS
┌────────────────────────────┐      ┌──────────────────────────────────┐
│ SwiftUI                      │      │ dsh web（DeepSeek Harness）      │
│  · Bot 团队列表  ◆/◇          │      │  └─ ds-bot 插件                  │
│  · 单 Bot 对话 + 输入条        │ HTTP │      · 长期活着的 Bot 团队         │
│  · 群聊列表 + 审批横幅         │─────▶│      · Bot 之间互相派活、群聊      │
│  · 完整界面（WKWebView 兜底）  │ POST │      · 工具审批、记忆、定时任务     │
└────────────────────────────┘      └──────────────────────────────────┘
              │  POST /api/bot   {endpoint, payload} → {ok, value}
              └─ 与官方 Web 界面完全同一条通道，宿主不需要任何改动
```

三层各管一件事：

| 层 | 来源 | 这里用到了什么 |
|---|---|---|
| 宿主 | DeepSeek Harness `dsh web` | HTTP 服务、登录 cookie、`/api/bot` 路由 |
| 业务 | `ds-bot` 插件 | 端点表、团队视图、对话消息项、审批语义 |
| 客户端 | grok-build-ios | SwiftUI 骨架、主题 token、PromptBar、权限横幅、MarkdownLite |

**为什么不把 Node 打进 App**：iOS 不允许长期驻留的后台 Node 运行时，App Store 也不接受自带解释器跑服务的形态。Grok 那个项目同样是这个结论——它把自己叫 *pager*（寻呼机）。所以这里的做法一致：原生界面负责看和说，重活留在宿主。

---

## 快速开始

### 1. 宿主侧（电脑或 NAS）

```bash
# 桌面版：直接打开 DeepSeek Bot
# 或者命令行：
npx @deepseek-ai/dsh@0.2.1-rc.2 plugin --profile web add ds-bot
npx @deepseek-ai/dsh@0.2.1-rc.2 web
```

启动后会打印：

```
dsh web: http://127.0.0.1:3080/?token=… (LAN: http://172.x.x.x:3080/?token=…)
```

把那行里的 `127.0.0.1` 换成**局域网 IP**（LAN 那行直接可用）。这个 token 会换成一个 30 天有效的签名 cookie。

### 2. 手机侧

1. 手机和电脑连同一个 Wi-Fi。
2. 打开 App，把整条 `http://<局域网IP>:3080/?token=…` 粘进去，点「连接宿主」。
3. 第一次会弹「本地网络」权限，**必须允许**，否则连不上。
4. 连上后就是团队列表；点一个 Bot 进去对话。

之后每次启动会自动重连上次的地址。

### 3. 编译 / 拿 IPA

本机是 Windows 的话编译不了 iOS——需要 macOS + Xcode（或直接让 CI 编）：

```bash
brew install xcodegen
xcodegen generate
open DeepSeekBot.xcodeproj      # 选一个开发团队签名，直接跑到手机上
```

只想要一个未签名的 IPA：

```bash
xcodebuild build -project DeepSeekBot.xcodeproj -scheme DeepSeekBot \
  -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

mkdir -p out/Payload && cp -R build/Build/Products/Release-iphoneos/DeepSeekBot.app out/Payload/
cd out && zip -qry DeepSeekBot-unsigned.ipa Payload
```

### 4. 装到 iPhone

未签名 IPA 需要自己签：

| 方式 | 需要 | 有效期 |
|---|---|---|
| **Sideloadly / AltStore / SideStore** | 一个 Apple ID（免费即可） | 7 天，到期重签 |
| Xcode 直接跑（数据线） | 免费 Apple ID | 7 天 |
| TestFlight / 真机分发 | 付费开发者账号（$99/年） | 90 天 |

免费账号够日常用，只是每 7 天要连一次电脑重签。

---

## 原生做了什么，什么交给「完整界面」

原生（走 `/api/bot`）：

- `state` — 团队快照、Bot 状态、待确认审批、只读标记，每 3 秒核对一次
- `chat` — 单个 Bot 的对话，分页往前翻（`cursor`）
- `send` — 发一句话给它
- `approval-answer` — 群聊成员的 `allow` / `reject`

交给 WKWebView（右上角「完整界面」）——这些在手机上用得少，但一个都不能缺：

- 群聊完整消息流、建群、拉人
- Bot 的回答卡片、工具调用细节
- 建 Bot / 改模型 / 记忆面板 / 定时任务 / 供应商密钥
- 卡片式提问（`questions`/`views` 的形状宿主还在演进，原生不去猜）

这个分工是故意的：宁可一个按钮跳到原版界面，也不做半真的复刻。

---

## 目录

```
project.yml                  XcodeGen 工程定义（.xcodeproj 是生成物，不入库）
Sources/
  DeepSeekBotApp.swift       入口；把 cookie 接受策略设成 always
  RootView.swift             屏幕路由 + 错误提示条
  TeamModel.swift            唯一的状态对象（形状对齐 grok 的 AppModel）
  Net/
    DSBClient.swift          POST /api/bot，信封解析，token→cookie 握手
    HostAddress.swift        粘贴地址的解析（可用性最容易被忽略的地方）
    DSBError.swift           宿主拒绝的原话直传
  Models/
    TeamView.swift           bots / rooms / work.approvals / models
    ChatPage.swift           bot|user|answer|event|divider
    Values.swift             Ignored、FlexibleList、DSBTime（容错解码）
    Chrome.swift             AppScreen、ConnectionPhase、审批选项、设置
  Views/
    OnboardingView.swift     连接页
    TeamListView.swift       团队列表（◆ 干活中 / ◇ 空闲）
    BotChatView.swift        对话 + PromptBar
    RoomListView.swift       群聊列表 + 审批
    SettingsView.swift       连接、外观、上游
    WebHostView.swift        完整界面
  Ported/                    取自 grok-build-ios 的文件（见 NOTICE）
Tests/DSBCoreTests.swift     地址解析、容错解码、消息项身份
docs/PROTOCOL.md             用到的端点与载荷
```

## CI

`.github/workflows/ios.yml` 在 `macos-15` 上跑：装 XcodeGen → 生成工程 → 模拟器跑单测 → 编译未签名设备包 → 打成 `.ipa` 传 artifact。打 tag 发 Release 时自动附到 Release 页。

---

## 已知限制

- **同一 Wi-Fi 才能连**。要让手机在外网也能用，得自己把 dsh 挂到反向代理上（宿主有 Host 信任围栏和登录 cookie，别裸奔）。
- **群聊只能看不能发**。`send` 需要会话 id，而房间的成员会话是隐藏的；与其猜错，不如跳到完整界面。
- 卡片式提问（`questions`）只提示「在等你回答」，回答仍需完整界面。
- Bot 浏览器读取（`browser-wait`）是桌面窗口的长轮询，手机不做。
- token 存在 App 沙盒的 UserDefaults 里，等价于宿主本地登录凭据；别把装了 App 的手机借人。

## 许可

Apache-2.0。上游归属见 `NOTICE`。
