// DeepSeek Bot for iOS — Apache-2.0
//
// The one state object, shaped after grok-build-ios's `AppModel` (screen, messages,
// draft, connectionPhase, permissionRequest, theme) so the two clients feel like one
// family — but every call underneath is DeepSeek Bot's, not ACP:
//
//   Grok (ACP over WebSocket)          DeepSeek Bot (POST /api/bot)
//   ─────────────────────────          ─────────────────────────────
//   session/new, session/prompt   →    send {sessionId, text}
//   session/list, dashboard       →    state → bots / rooms
//   scrollback updates            →    chat {botId, cursor} → items
//   session/request_permission    →    approval-answer {id, allow|reject}
//   setup: host + secret          →    login URL (?token=) → 30 天 cookie

import Foundation

@MainActor
final class TeamModel: ObservableObject {
    // Connection
    @Published var screen: AppScreen = .welcome
    @Published var connectionPhase: ConnectionPhase = .idle
    @Published var setupError: String?
    @Published var notice: String?
    @Published var loginDraft: String = ""
    @Published var tokenDraft: String = ""

    // Team
    @Published var team = TeamView()
    @Published var lastRefresh: Date?
    @Published var isRefreshing = false

    // The open Bot
    @Published var selectedBotId: String?
    @Published var botMessages: [ChatLine] = []
    @Published var chatCursor: ChatCursor?
    @Published var isLoadingOlder = false
    @Published var draft: String = ""
    @Published var isPromptFocused = false

    // Appearance
    @Published var isDark = DSBSettings.isDark {
        didSet { DSBSettings.isDark = isDark }
    }
    @Published var showTimestamps = DSBSettings.showTimestamps {
        didSet { DSBSettings.showTimestamps = showTimestamps }
    }

    private let client = DSBClient()
    private var pollTask: Task<Void, Never>?
    private var address: HostAddress?

    var theme: DSBTheme { isDark ? .night : .day }

    var connectedHost: String { address?.displayHost ?? "未连接" }

    /// The URL the web view loads; it is also what the phone used to authenticate.
    var loginURL: URL? { address?.loginURL }

    var selectedBot: Bot? { team.bot(selectedBotId) }

    var activeSessionId: String? { selectedBot?.sessionId }

    /// The line under the prompt: the Bot's model, its part count, and whether this
    /// host may only read the team (another dsh host holds it).
    var promptModelLine: String {
        guard let bot = selectedBot else { return "" }
        var pieces: [String] = []
        pieces.append(bot.model?.isEmpty == false ? bot.model! : "默认模型")
        if let effort = bot.effort, !effort.isEmpty { pieces.append(effort) }
        if let count = bot.parts?.count, count > 1 { pieces.append("第 \(count) 段") }
        if bot.waiting == true { pieces.append("等选模型") }
        if team.isReadOnly { pieces.append("只读") }
        return pieces.joined(separator: " · ")
    }

    // MARK: - Connect

    /// Runs at launch: reopen the last host without asking again.
    func restore() async {
        guard let saved = HostStore.load() else { return }
        address = saved
        loginDraft = saved.origin
        tokenDraft = saved.token ?? ""
        await open(saved, remember: false)
    }

    func connectFromDraft() async {
        guard let parsed = HostAddress.parse(loginDraft, token: tokenDraft) else {
            setupError = "填一个宿主地址，例如 192.168.1.5:3080，或 dsh 打印的带 token 的登录地址。"
            connectionPhase = .failed(setupError ?? "")
            return
        }
        await open(parsed, remember: true)
    }

    private func open(_ candidate: HostAddress, remember: Bool) async {
        connectionPhase = .checking
        setupError = nil
        notice = nil
        do {
            let view = try await client.connect(to: candidate)
            team = view
            address = candidate
            if remember { HostStore.save(candidate) }
            connectionPhase = .succeeded
            screen = .team
            lastRefresh = Date()
            startPolling()
        } catch {
            connectionPhase = .failed(error.localizedDescription)
            setupError = error.localizedDescription
        }
    }

    func disconnect() {
        pollTask?.cancel()
        pollTask = nil
        client.disconnect()
        HostStore.clear()
        address = nil
        team = TeamView()
        botMessages = []
        selectedBotId = nil
        connectionPhase = .idle
        setupError = nil
        screen = .welcome
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.refresh()
                if self.screen == .chat { await self.loadChat(silent: true) }
            }
        }
    }

    func refresh() async {
        guard client.isConnected, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let fresh: TeamView = try await client.call("state", ["locale": "zh-CN"], as: TeamView.self)
            if fresh.unchanged == true {
                // Only the `live()` half is new; the team itself is untouched.
                team.work = fresh.work
                team.questions = fresh.questions
                team.views = fresh.views
            } else {
                team = fresh
            }
            lastRefresh = Date()
            if connectionPhase != .succeeded { connectionPhase = .succeeded }
        } catch {
            connectionPhase = .failed(error.localizedDescription)
        }
    }

    // MARK: - A Bot's chat

    func openBot(_ bot: Bot) async {
        selectedBotId = bot.id
        botMessages = []
        chatCursor = nil
        draft = ""
        screen = .chat
        await loadChat()
    }

    func loadChat(silent: Bool = false) async {
        guard let botId = selectedBotId else { return }
        do {
            let page: ChatPage = try await client.call("chat", ["botId": botId], as: ChatPage.self)
            botMessages = Self.stableLines(page.lines)
            chatCursor = page.cursor
        } catch {
            if !silent { notice = error.localizedDescription }
        }
    }

    func loadOlder() async {
        guard let botId = selectedBotId, let cursor = chatCursor, !isLoadingOlder else { return }
        isLoadingOlder = true
        defer { isLoadingOlder = false }
        var payload: [String: Any] = ["botId": botId]
        var raw: [String: Any] = [:]
        if let part = cursor.part { raw["part"] = part }
        if let seq = cursor.beforeSeq { raw["beforeSeq"] = seq }
        if !raw.isEmpty { payload["cursor"] = raw }
        do {
            let page: ChatPage = try await client.call("chat", payload, as: ChatPage.self)
            botMessages = Self.stableLines(page.lines + botMessages.map(\.item))
            chatCursor = page.cursor
        } catch {
            notice = error.localizedDescription
        }
    }

    /// The host's items carry no ids, and this client replaces the whole page on every
    /// poll. Identity is therefore content-derived: same text at the same time keeps its
    /// row, so a 3-second refresh does not rebuild (and un-scroll) the conversation.
    static func stableLines(_ items: [ChatItem]) -> [ChatLine] {
        var seen: [String: Int] = [:]
        return items.map { item in
            let stamp = item.time?.date?.timeIntervalSince1970 ?? 0
            let base = "\(item.kind ?? "")|\(item.role ?? "")|\(stamp)|\(item.text ?? item.placeholder)"
            let occurrence = (seen[base] ?? 0) + 1
            seen[base] = occurrence
            return ChatLine(id: "\(base)#\(occurrence)", item: item)
        }
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let sessionId = activeSessionId else {
            notice = "这个 Bot 还没有自己的会话，先在完整界面里打开一次。"
            return
        }
        guard !team.isReadOnly else {
            notice = team.readOnly ?? "这个宿主只能读，不能发消息。"
            return
        }
        draft = ""
        do {
            try await client.callVoid("send", ["sessionId": sessionId, "text": text])
            await loadChat(silent: true)
        } catch {
            draft = text
            notice = error.localizedDescription
        }
    }

    // MARK: - Approvals

    func answer(_ approval: Approval, choice: String) async {
        guard let id = approval.id else { return }
        do {
            try await client.callVoid("approval-answer", ["id": id, "choice": choice])
            await refresh()
        } catch {
            notice = error.localizedDescription
        }
    }

    // MARK: - Presentation helpers

    func permissionRequest(for approval: Approval) -> PermissionRequest {
        PermissionRequest(
            message: approval.detail,
            title: approval.title,
            requestId: approval.id
        )
    }

    func clearNotice() {
        notice = nil
    }
}
