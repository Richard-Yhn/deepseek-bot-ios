// DeepSeek Bot for iOS — Apache-2.0
// What a room reports while it runs.
//
//   room-progress { roomId }  →  [{ callId, replies, speaking }]
//                                 (ds-bot/src/host/channel.js — room-progress)
//
// A room's message log is *not* on this channel: `view()` destructures `log` out of
// every room and keeps only `preview`, and `chat`/`earlier` both gate on `botOf(id)`,
// which a room id never satisfies. The desktop window shows the full transcript because
// it runs inside DSH's own web client and subscribes to session events directly.
// Over `/api/bot` the phone gets: send, live progress, approvals — and the transcript
// through the web view.

import Foundation

struct RoomProgress: Decodable, Identifiable {
    var callId: String?
    var replies: Int?
    /// The member whose turn is running, when the host says so.
    var speaking: String?

    init() {}

    var id: String { callId ?? "call" }
}

/// A page of a room's own transcript, from the `room-log` endpoint this repo carries a
/// patch for (`patches/room-log.patch`). Hosts without the patch answer
/// `Unknown endpoint room-log`, and the room screen keeps its web-view fallback.
struct RoomLogPage: Decodable {
    var seq: Int?
    var kept: Int?
    var limit: Int?
    var lines: [RoomLine]?
    var cursor: RoomLogCursor?

    init() {}

    var list: [RoomLine] { lines ?? [] }
}

struct RoomLogCursor: Decodable {
    var before: Int?
}

/// One kept line. `seq` is the room's own counter, so it is the row identity and the
/// paging cursor; `length` is set only when the host cut the text in `state`.
struct RoomLine: Decodable, Identifiable {
    var seq: Int?
    var who: String?
    var botId: String?
    var kind: String?
    var length: Int?
    var text: String?
    var files: Ignored?

    init() {}

    var id: Int { seq ?? 0 }
    var isUser: Bool { (who ?? "") == "User" }
    var displayName: String {
        let name = (who ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "成员" : name
    }
    /// A line with a kind and no text is a marker: a lookup, a join, a handoff.
    var isMarker: Bool {
        guard kind != nil else { return false }
        return (text ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }
    var markerText: String {
        switch kind ?? "" {
        case "lookup": return "查了群里的记录"
        case "join": return "加入了群聊"
        case "leave": return "离开了群聊"
        default: return "· \(kind ?? "事件")"
        }
    }
    var wasCut: Bool {
        guard let length else { return false }
        return length > (text ?? "").count
    }
}
