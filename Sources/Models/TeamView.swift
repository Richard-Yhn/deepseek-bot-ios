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

struct Bot: Decodable {
    var id: String?
    var name: String?
    var role: String?
    var color: String?
    var avatar: String?
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
