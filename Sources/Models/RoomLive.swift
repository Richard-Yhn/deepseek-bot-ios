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
