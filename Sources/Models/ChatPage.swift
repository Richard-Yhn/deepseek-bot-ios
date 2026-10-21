// DeepSeek Bot for iOS — Apache-2.0
// A Bot's own chat as the host draws it (ds-bot/src/host/parts.js — displayItems).
// Kinds: bot | user | answer | event | divider. One entry per text block, which is
// why the web UI shows several bubbles in a row for one turn.

import Foundation

struct ChatPage: Decodable {
    var sessionId: String?
    var items: [ChatItem]?
    var cursor: ChatCursor?

    init() {}

    var lines: [ChatItem] { items ?? [] }
}

/// Opaque paging cursor; sent straight back to `chat`.
struct ChatCursor: Decodable, Equatable {
    var part: Int?
    var beforeSeq: Int?
}

/// A rendered row. Identity is derived from the item's content (see
/// `TeamModel.stableLines`) so a periodic refresh does not rebuild the list.
struct ChatLine: Identifiable, Equatable {
    let id: String
    let item: ChatItem
}

struct ChatItem: Decodable, Identifiable, Equatable {
    enum Kind: String {
        case bot
        case user
        case answer
        case event
        case divider
    }

    var kind: String?
    var text: String?
    var time: DSBTime?
    var images: Int?
    /// event only: request | reply | report | stopped
    var role: String?
    var name: String?
    var botId: String?
    var roomId: String?
    var questions: Ignored?
    var views: Ignored?
    var answers: Ignored?

    /// Row identity for SwiftUI. The host's items carry no id, and a synthesized
    /// decoder would insist on one, so this type decodes itself.
    let id = UUID()

    init() {}

    private enum CodingKeys: String, CodingKey {
        case kind, text, time, images, role, name, botId, roomId, questions, views, answers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        time = try container.decodeIfPresent(DSBTime.self, forKey: .time)
        images = try container.decodeIfPresent(Int.self, forKey: .images)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        botId = try container.decodeIfPresent(String.self, forKey: .botId)
        roomId = try container.decodeIfPresent(String.self, forKey: .roomId)
        questions = try container.decodeIfPresent(Ignored.self, forKey: .questions)
        views = try container.decodeIfPresent(Ignored.self, forKey: .views)
        answers = try container.decodeIfPresent(Ignored.self, forKey: .answers)
    }

    static func == (lhs: ChatItem, rhs: ChatItem) -> Bool {
        lhs.id == rhs.id
    }

    var parsed: Kind { Kind(rawValue: kind ?? "bot") ?? .bot }

    var isUser: Bool { parsed == .user }

    /// An answered card — the host keeps no plain text for it.
    var placeholder: String {
        if parsed == .answer {
            if let text, !text.isEmpty { return text }
            if views != nil { return "（已填写卡片）" }
            return "（已作答）"
        }
        if parsed == .event {
            switch role ?? "" {
            case "request": return "↗ 分派给 \(name ?? "队友")"
            case "reply": return "↩︎ \(name ?? "队友") 回报"
            case "report": return "· \(name ?? "队友") 汇报"
            case "stopped": return "· 已停止"
            default: return "· \(name ?? "事件")"
            }
        }
        return ""
    }
}
