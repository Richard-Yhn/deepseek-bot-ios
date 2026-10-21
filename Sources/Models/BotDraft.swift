// DeepSeek Bot for iOS — Apache-2.0
// What the app sends when it creates or edits a Bot. Field names and limits are the
// host's own (ds-bot/src/host/roster.js — buildBot / updateBot):
//
//   name       ≤ 40 chars, unique in the team
//   role       ≤ 24 chars
//   color      an ink *name* from constants.js, never a hex
//   brief      the one-line assignment the Bot keeps in its prompt
//   instructions  the longer standing order
//   model      a catalog ref `provider/model` — this is how a Bot gets a custom model
//   effort     a thinking level of that model; null clears it
//   workDir    a folder the team already knows (or one the host can resolve)

import Foundation

struct BotDraft {
    var editingId: String?
    var name: String = ""
    var role: String = ""
    var color: String = "deepseek"
    var brief: String = ""
    var instructions: String = ""
    var model: String = ""
    var effort: String = ""
    var workDir: String = ""
    /// Create with no model at all: the Bot then waits for its model to be chosen.
    var pickModelLater: Bool = false

    init() {}

    init(bot: Bot) {
        editingId = bot.id
        name = bot.name ?? ""
        role = bot.role ?? ""
        color = bot.color ?? "deepseek"
        brief = bot.brief ?? ""
        instructions = bot.instructions ?? ""
        model = bot.model ?? ""
        effort = bot.effort ?? ""
        workDir = bot.workDir ?? ""
    }

    var isEditing: Bool { editingId != nil }

    var trimmedName: String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }

    var trimmedRole: String {
        String(role.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
    }

    var canSubmit: Bool { !trimmedName.isEmpty }

    /// The assignment this Bot is given, as the team list shows it.
    var assignmentSummary: String {
        let task = brief.trimmingCharacters(in: .whitespacesAndNewlines)
        if !task.isEmpty { return task }
        let roleText = role.trimmingCharacters(in: .whitespacesAndNewlines)
        return roleText.isEmpty ? "还没有分配任务" : roleText
    }

    func createPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "name": trimmedName,
            "role": trimmedRole,
            "color": color,
            "brief": brief.trimmingCharacters(in: .whitespacesAndNewlines),
            "instructions": instructions.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        let ref = model.trimmingCharacters(in: .whitespaces)
        if !ref.isEmpty {
            payload["model"] = ref
            let level = effort.trimmingCharacters(in: .whitespaces)
            if !level.isEmpty { payload["effort"] = level }
        } else if pickModelLater {
            payload["pickModel"] = true
        }
        let dir = workDir.trimmingCharacters(in: .whitespaces)
        if !dir.isEmpty { payload["workDir"] = dir }
        return payload
    }

    func updatePayload() -> [String: Any] {
        var payload: [String: Any] = [
            "name": trimmedName,
            "role": trimmedRole,
            "color": color,
            "brief": brief.trimmingCharacters(in: .whitespacesAndNewlines),
            "instructions": instructions.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        let ref = model.trimmingCharacters(in: .whitespaces)
        // `null` is the host's word for "clear it", not for "leave it alone".
        payload["model"] = ref.isEmpty ? (NSNull() as Any) : (ref as Any)
        let level = effort.trimmingCharacters(in: .whitespaces)
        payload["effort"] = level.isEmpty ? (NSNull() as Any) : (level as Any)
        let dir = workDir.trimmingCharacters(in: .whitespaces)
        if !dir.isEmpty { payload["workDir"] = dir }
        return payload
    }
}

/// One Bot's line in a dispatch: a shared task plus a per-Bot note, so several Bots
/// can be given different angles on the same job at once.
struct DispatchTarget: Identifiable {
    let id: String
    var bot: Bot
    var selected: Bool
    var note: String

    init(bot: Bot) {
        id = bot.uid
        self.bot = bot
        selected = false
        note = ""
    }

    var modelLabel: String {
        guard let model = bot.model, !model.isEmpty else { return "默认模型" }
        if let slash = model.firstIndex(of: "/") {
            return String(model[model.index(after: slash)...])
        }
        return model
    }
}
