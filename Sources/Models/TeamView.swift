// DeepSeek Bot for iOS — Apache-2.0
// The `state` answer, cut down to what a phone draws.
// Field-for-field source of truth: ds-bot/src/host/channel.js — view() and live().

import Foundation

struct TeamView: Decodable {
    var revision: Int?
    /// True when the host answered a `since` ask and nothing structural changed;
    /// only the `live()` half is fresh.
    var unchanged: Bool?
    var mainBotId: String?
    var mainBotIds: [String]?
    var bots: [Bot]?
    var rooms: [Room]?
    var models: [ModelEntry]?
    var defaultModel: String?
    var questions: [String: Ignored]?
    var views: [String: Ignored]?
    var work: Work?
    var prefs: Prefs?
    var readOnly: String?
    var memory: Bool?

    init() {}

    var botList: [Bot] { bots ?? [] }
    var roomList: [Room] { rooms ?? [] }
    var modelList: [ModelEntry] { models ?? [] }
    var approvalList: [Approval] { work?.approvalList ?? [] }
    var isReadOnly: Bool { readOnly != nil }

    func bot(_ id: String?) -> Bot? {
        guard let id else { return nil }
        return botList.first { $0.id == id }
    }

    func isMain(_ bot: Bot) -> Bool {
        guard let id = bot.id else { return false }
        return (mainBotIds ?? []).contains(id)
    }

    /// Catalog grouped by provider, ordered the way the host lists providers.
    var modelGroups: [ModelGroup] {
        var order: [String] = []
        var byProvider: [String: [ModelEntry]] = [:]
        for entry in modelList {
            let key = entry.providerTitle
            if byProvider[key] == nil { order.append(key) }
            byProvider[key, default: []].append(entry)
        }
        return order.map { ModelGroup(id: $0, title: $0, models: byProvider[$0] ?? []) }
    }

    /// True when a model ref comes from a provider the user added (`provider-add`).
    func isCustomModel(_ ref: String?) -> Bool {
        guard let ref else { return false }
        guard let entry = modelList.first(where: { $0.ref == ref }) else { return false }
        guard let providerName = entry.providerName, !providerName.isEmpty else { return false }
        // The host ships DeepSeek's own providers; anything else here was added.
        let builtin = ["deepseek", "DeepSeek", "deepseek-ai"]
        return !builtin.contains(providerName) && !builtin.contains(entry.provider ?? "")
    }

    /// Which Bots hold a turn right now (`work.bots`, per Bot in the host's view).
    func isWorking(_ bot: Bot) -> Bool {
        guard let id = bot.id, let working = work?.bots else { return false }
        return working[id] != nil
    }
}

/// `bots[].avatar` is an object — `{"shape": "whale"}`, optionally with `image` — and has
/// been since 0.1.x. It is not a string. A plain string is still accepted, because a
/// hand-edited state file or an older host may carry just the shape name.
struct BotAvatar: Decodable, Equatable {
    var shape: String?
    var image: String?

    init(shape: String? = nil, image: String? = nil) {
        self.shape = shape
        self.image = image
    }

    private enum CodingKeys: String, CodingKey {
        case shape, image
    }

    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let text = try? single.decode(String.self) {
            shape = text
            image = nil
            return
        }
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            shape = nil
            image = nil
            return
        }
        shape = (try? container.decodeIfPresent(String.self, forKey: .shape)) ?? nil
        image = (try? container.decodeIfPresent(String.self, forKey: .image)) ?? nil
    }
}

struct Bot: Decodable {
    var id: String?
    var name: String?
    var role: String?
    var color: String?
    var avatar: BotAvatar?
    var model: String?
    var effort: String?
    var sessionId: String?
    var parts: [String]?
    /// The Bot holds its greeting until the user picks its model.
    var waiting: Bool?
    var brief: String?
    /// The standing order, kept by the host on every Bot (roster.js — buildBot).
    var instructions: String?
    var workDir: String?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case id, name, role, color, avatar, model, effort, sessionId, parts, waiting,
             brief, instructions, workDir
    }

    /// Every field is decoded on its own. One field arriving in a shape this build does
    /// not know costs that field, not the whole Bot — and a Bot that failed entirely
    /// would take the whole `bots` array with it, which is how "宿主返回的内容无法解析"
    /// replaced the team list on screen.
    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? nil
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        role = (try? container.decodeIfPresent(String.self, forKey: .role)) ?? nil
        color = (try? container.decodeIfPresent(String.self, forKey: .color)) ?? nil
        avatar = (try? container.decodeIfPresent(BotAvatar.self, forKey: .avatar)) ?? nil
        model = (try? container.decodeIfPresent(String.self, forKey: .model)) ?? nil
        effort = (try? container.decodeIfPresent(String.self, forKey: .effort)) ?? nil
        sessionId = (try? container.decodeIfPresent(String.self, forKey: .sessionId)) ?? nil
        parts = (try? container.decodeIfPresent([String].self, forKey: .parts)) ?? nil
        waiting = (try? container.decodeIfPresent(Bool.self, forKey: .waiting)) ?? nil
        brief = (try? container.decodeIfPresent(String.self, forKey: .brief)) ?? nil
        instructions = (try? container.decodeIfPresent(String.self, forKey: .instructions)) ?? nil
        workDir = (try? container.decodeIfPresent(String.self, forKey: .workDir)) ?? nil
    }

    var uid: String { id ?? name ?? "bot" }
    var displayName: String {
        if let name, !name.isEmpty { return name }
        if let role, !role.isEmpty { return role }
        return "Bot"
    }
    var subtitle: String {
        var pieces: [String] = []
        if let role, !role.isEmpty { pieces.append(role) }
        if let model, !model.isEmpty { pieces.append(model) }
        return pieces.joined(separator: " · ")
    }
}

struct Room: Decodable {
    var id: String?
    var name: String?
    var members: [String]?
    var preview: String?
    var mode: String?
    var notice: String?
    var admin: String?
    var sessionId: String?
    var parts: [String]?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case id, name, members, preview, mode, notice, admin, sessionId, parts
    }

    /// Field by field, like `Bot`: one surprising shape must not cost the room list.
    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? nil
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        members = (try? container.decodeIfPresent([String].self, forKey: .members)) ?? nil
        preview = (try? container.decodeIfPresent(String.self, forKey: .preview)) ?? nil
        mode = (try? container.decodeIfPresent(String.self, forKey: .mode)) ?? nil
        notice = (try? container.decodeIfPresent(String.self, forKey: .notice)) ?? nil
        admin = (try? container.decodeIfPresent(String.self, forKey: .admin)) ?? nil
        sessionId = (try? container.decodeIfPresent(String.self, forKey: .sessionId)) ?? nil
        parts = (try? container.decodeIfPresent([String].self, forKey: .parts)) ?? nil
    }

    var uid: String { id ?? name ?? "room" }
    var displayName: String {
        if let name, !name.isEmpty { return name }
        return "群聊"
    }
    var memberCount: Int { members?.count ?? 0 }
}

struct ModelEntry: Decodable, Identifiable {
    var ref: String?
    var name: String?
    var label: String?
    var needsKey: Bool?
    var provider: String?
    var providerName: String?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case ref, name, label, needsKey, provider, providerName
    }

    /// Same rule as `Bot`: the model catalog is the host's to change, and one entry in
    /// an unknown shape must not empty the picker — or the team with it.
    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        ref = (try? container.decodeIfPresent(String.self, forKey: .ref)) ?? nil
        name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? nil
        needsKey = (try? container.decodeIfPresent(Bool.self, forKey: .needsKey)) ?? nil
        provider = (try? container.decodeIfPresent(String.self, forKey: .provider)) ?? nil
        providerName = (try? container.decodeIfPresent(String.self, forKey: .providerName)) ?? nil
    }

    var id: String { ref ?? label ?? name ?? "model" }
    var title: String { label ?? name ?? ref ?? "模型" }
    /// `provider/model` → `model`, which is what a person calls it.
    var shortName: String {
        guard let ref, let slash = ref.firstIndex(of: "/") else { return title }
        return String(ref[ref.index(after: slash)...])
    }
    var providerTitle: String { providerName ?? provider ?? "默认" }
}

/// The catalog grouped by provider — a Bot's model is picked per provider, and that is
/// also how a custom endpoint shows up: as one more group.
struct ModelGroup: Identifiable {
    let id: String
    let title: String
    let models: [ModelEntry]
}

struct Prefs: Decodable {
    var theme: String?
    var accent: String?
    var motion: String?
}

/// `live().work` — what moves without a new revision.
struct Work: Decodable {
    var bots: [String: Ignored]?
    var rooms: [String: Ignored]?
    var approvals: FlexibleList<Approval>?
    var waiting: [String: Ignored]?
    var turns: [String: DSBTime]?

    init() {}

    var approvalList: [Approval] { approvals?.items ?? [] }
}

/// One pending tool approval (ds-bot/src/host/approvals.js). Only group Sessions put
/// their requests here — a Bot's own chat keeps DSH's own card.
struct Approval: Decodable, Identifiable {
    var id: String?
    var sessionId: String?
    var botId: String?
    var roomId: String?
    var tool: String?
    var reason: String?
    var answerable: Bool?
    var at: DSBTime?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case id, sessionId, botId, roomId, tool, reason, answerable, at
    }

    /// Tolerant on purpose: an approval that fails to decode would be dropped from a
    /// `FlexibleList` without a word, and the user would never see the question.
    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        id = (try? container.decodeIfPresent(String.self, forKey: .id)) ?? nil
        sessionId = (try? container.decodeIfPresent(String.self, forKey: .sessionId)) ?? nil
        botId = (try? container.decodeIfPresent(String.self, forKey: .botId)) ?? nil
        roomId = (try? container.decodeIfPresent(String.self, forKey: .roomId)) ?? nil
        tool = (try? container.decodeIfPresent(String.self, forKey: .tool)) ?? nil
        reason = (try? container.decodeIfPresent(String.self, forKey: .reason)) ?? nil
        answerable = (try? container.decodeIfPresent(Bool.self, forKey: .answerable)) ?? nil
        at = (try? container.decodeIfPresent(DSBTime.self, forKey: .at)) ?? nil
    }

    var uid: String { id ?? "approval" }
    var title: String {
        if let tool, !tool.isEmpty { return "\(tool) 需要确认" }
        return "工具调用需要确认"
    }
    var detail: String {
        if let reason, !reason.isEmpty { return reason }
        return "允许之后，这一轮才会继续。"
    }
}
