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
    @Published var isBusy = false
    @Published var providers = ProviderDirectory()
    /// The team's revision, sent back as `since` so an unchanged answer stays cheap.
    private(set) var revision: Int?

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
                guard let self else { return }
                try? await Task.sleep(nanoseconds: self.pollInterval)
                guard !Task.isCancelled else { return }
                await self.refresh()
                if self.screen == .chat { await self.loadChat(silent: true) }
                if self.screen == .room {
                    await self.loadRoomProgress()
                    await self.loadRoomLog()
                }
            }
        }
    }

    /// Fast while someone is working or a conversation is open, slow when the team is
    /// idle. `since` keeps the idle ticks cheap: an unchanged answer is a few hundred
    /// bytes of `live()` state.
    private var pollInterval: UInt64 {
        if screen == .chat || screen == .room { return 1_200_000_000 }
        if team.botList.contains(where: { team.isWorking($0) }) { return 1_500_000_000 }
        return 4_000_000_000
    }

    /// `force` drops `since` and asks for the whole team — used after every mutation,
    /// because a changed field does not always bump the revision the client last saw.
    func refresh(force: Bool = false) async {
        guard client.isConnected, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var payload: [String: Any] = ["locale": "zh-CN"]
        if !force, let revision { payload["since"] = revision }
        do {
            let fresh: TeamView = try await client.call("state", payload, as: TeamView.self)
            if fresh.unchanged == true {
                // Only the `live()` half is new; the team itself is untouched.
                team.work = fresh.work
                team.questions = fresh.questions
                team.views = fresh.views
                if let value = fresh.revision { revision = value }
            } else {
                team = fresh
                revision = fresh.revision
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

    // MARK: - Managing the team
    //
    // Every Bot is its own root Session on the host, which is what makes "many Bots at
    // once" work: dispatching to five Bots is five `send` calls, and the host runs the
    // five turns in parallel. Each Bot carries its own model ref, so one can run on the
    // DeepSeek default while another runs on a custom provider added with `provider-add`.

    func createBot(_ draft: BotDraft) async -> Bool {
        guard draft.canSubmit else {
            notice = "先给这个 Bot 起个名字。"
            return false
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.callVoid("create-bot", draft.createPayload())
            await refresh(force: true)
            await loadProviders()
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    func updateBot(_ draft: BotDraft) async -> Bool {
        guard let id = draft.editingId, draft.canSubmit else { return false }
        isBusy = true
        defer { isBusy = false }
        var payload = draft.updatePayload()
        payload["id"] = id
        do {
            try await client.callVoid("update-bot", payload)
            await refresh(force: true)
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    func deleteBot(_ bot: Bot) async -> Bool {
        guard let id = bot.id else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.callVoid("delete-bot", ["id": id])
            if selectedBotId == id {
                selectedBotId = nil
                botMessages = []
                screen = .team
            }
            await refresh(force: true)
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    func setMain(_ bot: Bot, primary: Bool = false) async -> Bool {
        guard let id = bot.id else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.callVoid("set-main", ["id": id, "main": true, "primary": primary])
            await refresh(force: true)
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    func createRoom(name: String, members: [String], admin: String?, greet: Bool) async -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, members.count >= 2 else {
            notice = "群聊要有名字，至少两个成员。"
            return false
        }
        isBusy = true
        defer { isBusy = false }
        var payload: [String: Any] = ["name": clean, "members": members, "greet": greet]
        if let admin, !admin.isEmpty { payload["admin"] = admin }
        do {
            try await client.callVoid("create-room", payload)
            await refresh(force: true)
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    func deleteRoom(_ room: Room) async -> Bool {
        guard let id = room.id else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.callVoid("delete-room", ["id": id])
            await refresh(force: true)
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    // MARK: - Handing work out

    /// Sends one job to several Bots at once, with a per-Bot angle. The host queues each
    /// turn on that Bot's own Session, so they really do run in parallel.
    func dispatch(_ task: String, targets: [DispatchTarget]) async -> String {
        let body = task.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "先写一句要做什么。" }
        let chosen = targets.filter { $0.selected }
        guard !chosen.isEmpty else { return "没有勾选 Bot。" }
        var sent = 0
        var skipped: [String] = []
        var failed: [String] = []
        for target in chosen {
            guard let sessionId = target.bot.sessionId else {
                skipped.append(target.bot.displayName)
                continue
            }
            let note = target.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let text = note.isEmpty ? body : "\(body)\n\n你负责的这一份：\(note)"
            do {
                try await client.callVoid("send", ["sessionId": sessionId, "text": text])
                sent += 1
            } catch {
                failed.append("\(target.bot.displayName)（\(error.localizedDescription)）")
            }
        }
        await refresh(force: true)
        if !failed.isEmpty {
            return "发出 \(sent) 个，失败 \(failed.count) 个：\(failed.joined(separator: "；"))"
        }
        if !skipped.isEmpty {
            return "发出 \(sent) 个；\(skipped.joined(separator: "、")) 还没有会话，先在完整界面打开一次。"
        }
        return "已派给 \(sent) 个 Bot，它们各自在宿主上并行跑。"
    }

    // MARK: - Room chats
    //
    // A room IS a Session on the host, and its id is that session's id — the official
    // client sends with `room.id` (client/new-chat.js: `actions.send(room.id, text)`,
    // which team-actions maps to `call('send', { sessionId, text })`). So the phone can
    // post into a group chat over the same endpoint a Bot chat uses.
    //
    // What it cannot do is read the group's history: `view()` strips each room's `log`
    // and keeps `preview`, and `chat`/`earlier` only answer for a Bot's own Session.
    // Live progress is exposed though, so a running room still shows who is speaking.

    @Published var selectedRoomId: String?
    @Published var roomDraft = ""
    @Published var roomProgress: [RoomProgress] = []
    @Published var isRoomSending = false

    /// The room's own transcript, when the host carries the `room-log` patch
    /// (`patches/room-log.patch`). `roomLogSupported` stays true for an unpatched host
    /// until one call answers `Unknown endpoint room-log`.
    @Published var roomLines: [RoomLine] = []
    @Published var roomCursor: Int?
    @Published var roomLogSupported = true
    @Published var isLoadingRoomLog = false
    private(set) var roomKept: Int = 0

    var selectedRoom: Room? {
        guard let id = selectedRoomId else { return nil }
        return team.roomList.first { $0.id == id }
    }

    var isRoomRunning: Bool {
        guard let id = selectedRoomId else { return false }
        return team.work?.rooms?[id] != nil
    }

    func openRoom(_ room: Room) async {
        selectedRoomId = room.id
        roomDraft = ""
        roomProgress = []
        roomLines = []
        roomCursor = nil
        screen = .room
        await loadRoomProgress()
        await loadRoomLog()
    }

    /// The newest page, merged in. Polling calls this, so new lines arrive without
    /// throwing away the older pages the user already paged back to.
    func loadRoomLog() async {
        guard let id = selectedRoomId else { return }
        do {
            let page: RoomLogPage = try await client.call(
                "room-log", ["roomId": id, "limit": 20], as: RoomLogPage.self
            )
            mergeRoomLog(page)
            roomLogSupported = true
            if roomCursor == nil { roomCursor = page.cursor?.before }
        } catch {
            // An unpatched host is a state, not a failure: the room screen says so.
            if error.localizedDescription.contains("Unknown endpoint") {
                roomLogSupported = false
            }
        }
    }

    /// The page older than what we hold, prepended.
    func loadOlderRoomLines() async {
        guard let id = selectedRoomId, let before = roomCursor, !isLoadingRoomLog else { return }
        isLoadingRoomLog = true
        defer { isLoadingRoomLog = false }
        do {
            let page: RoomLogPage = try await client.call(
                "room-log", ["roomId": id, "limit": 20, "before": before], as: RoomLogPage.self
            )
            mergeRoomLog(page)
            roomCursor = page.cursor?.before
        } catch {
            notice = error.localizedDescription
        }
    }

    private func mergeRoomLog(_ page: RoomLogPage) {
        var bySeq: [Int: RoomLine] = [:]
        for line in roomLines where line.seq != nil { bySeq[line.seq ?? 0] = line }
        for line in page.list where line.seq != nil { bySeq[line.seq ?? 0] = line }
        roomLines = bySeq.values.sorted { ($0.seq ?? 0) < ($1.seq ?? 0) }
        if let kept = page.kept { roomKept = kept }
    }

    func loadRoomProgress() async {
        guard let id = selectedRoomId else { return }
        do {
            roomProgress = try await client.call("room-progress", ["roomId": id], as: [RoomProgress].self)
        } catch {
            roomProgress = []
        }
    }

    func sendToRoom() async {
        let text = roomDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let id = selectedRoomId else { return }
        guard !team.isReadOnly else {
            notice = team.readOnly ?? "这个宿主只能读，不能发消息。"
            return
        }
        isRoomSending = true
        defer { isRoomSending = false }
        do {
            try await client.callVoid("send", ["sessionId": id, "text": text])
            roomDraft = ""
            await refresh(force: true)
            await loadRoomProgress()
            await loadRoomLog()
        } catch {
            notice = error.localizedDescription
        }
    }

    /// Stops one member's turn inside a room (`stop-member-work { roomId, botId }`).
    func stopMember(in room: Room, botId: String) async {
        guard let id = room.id else { return }
        do {
            try await client.callVoid("stop-member-work", ["roomId": id, "botId": botId])
            await refresh(force: true)
            await loadRoomProgress()
        } catch {
            notice = error.localizedDescription
        }
    }

    /// Member ids → the Bots they name, in the room's own order.
    func members(of room: Room) -> [Bot] {
        (room.members ?? []).compactMap { team.bot($0) }
    }

    // MARK: - Models, providers, folders

    /// A model's thinking levels. Asked per model ref, because they belong to the model.
    func loadEfforts(for ref: String) async -> EffortCatalog {
        guard !ref.isEmpty else { return EffortCatalog() }
        do {
            return try await client.call("efforts", ["ref": ref], as: EffortCatalog.self)
        } catch {
            return EffortCatalog()
        }
    }

    /// The folders the team already works in, for a Bot's workDir.
    func loadFolders() async -> FolderCatalog {
        do {
            return try await client.call("folders", [:], as: FolderCatalog.self)
        } catch {
            return FolderCatalog()
        }
    }

    func loadProviders() async {
        guard client.isConnected else { return }
        do {
            providers = try await client.call("providers", [:], as: ProviderDirectory.self)
        } catch {
            // `providers` is unanswerable on a host without DSH's settings seams; that is
            // a state, not a failure worth a banner.
            providers = ProviderDirectory()
        }
    }

    func setProviderKey(_ provider: Provider, value: String?) async -> Bool {
        guard let id = provider.id else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            var payload: [String: Any] = ["provider": id]
            if let value { payload["value"] = value } else { payload["value"] = NSNull() }
            try await client.callVoid("provider-key", payload)
            await loadProviders()
            await refresh(force: true)
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    /// Adds a provider DSH ships nothing about: an endpoint you run, or a vendor it does
    /// not know. This is what "a Bot on a custom model" starts with.
    func addCustomProvider(
        id: String,
        name: String,
        baseURL: String,
        api: String,
        key: String,
        modelIds: [String]
    ) async -> Bool {
        let route = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let endpoint = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = modelIds
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !route.isEmpty, !endpoint.isEmpty, !ids.isEmpty else {
            notice = "供应商 id、接口地址、至少一个模型 id 都要填。"
            return false
        }
        isBusy = true
        defer { isBusy = false }
        var payload: [String: Any] = [
            "provider": route,
            "custom": true,
            "api": api,
            "baseURL": endpoint,
            "models": ids.map { ["id": $0] },
        ]
        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty { payload["name"] = displayName }
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secret.isEmpty { payload["key"] = secret }
        do {
            providers = try await client.call("provider-add", payload, as: ProviderDirectory.self)
            await refresh(force: true)
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    func removeProvider(_ provider: Provider) async -> Bool {
        guard let id = provider.id else { return false }
        isBusy = true
        defer { isBusy = false }
        do {
            providers = try await client.call("provider-remove", ["provider": id], as: ProviderDirectory.self)
            await refresh(force: true)
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    /// Asks the endpoint what it serves. The key typed for this goes with the question
    /// and is not stored (`discoverModels` in providers.js).
    func discoverModels(baseURL: String, api: String, key: String) async -> [DiscoveredModel] {
        var payload: [String: Any] = ["baseURL": baseURL.trimmingCharacters(in: .whitespacesAndNewlines)]
        if !api.isEmpty { payload["api"] = api }
        let secret = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secret.isEmpty { payload["key"] = secret }
        do {
            let found = try await client.call("provider-models", payload, as: [DiscoveredModel].self)
            return found
        } catch {
            notice = error.localizedDescription
            return []
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
