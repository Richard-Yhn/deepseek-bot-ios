// DeepSeek Bot for iOS — Apache-2.0
// The host's team file is a JSON document that grows fields every release. A phone
// that refuses to open the team because one unfamiliar field changed shape would be
// useless, so the decoding here is deliberately tolerant: unknown values are ignored,
// lists accept either an array or an object keyed by id, and times accept the three
// shapes DSH has used (epoch ms, epoch s, ISO 8601).

import Foundation

/// Swallows any JSON value — present or absent, object, array, string, number.
/// Used where the host sends something this client does not render.
struct Ignored: Decodable, Equatable {
    init() {}
    init(from decoder: Decoder) throws {}
}

/// An array on the wire, or an object keyed by id. Never throws: a malformed list
/// degrades to an empty one instead of breaking the whole team view.
struct FlexibleList<Element: Decodable>: Decodable {
    var items: [Element]

    init(items: [Element] = []) {
        self.items = items
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.singleValueContainer() else {
            items = []
            return
        }
        if let array = try? container.decode([Element].self) {
            items = array
            return
        }
        if let keyed = try? container.decode([String: Element].self) {
            items = Array(keyed.values)
            return
        }
        items = []
    }
}

/// A timestamp in whichever shape the host writes it.
struct DSBTime: Decodable, Equatable {
    let date: Date?

    init(date: Date? = nil) {
        self.date = date
    }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.singleValueContainer() else {
            date = nil
            return
        }
        if let number = try? container.decode(Double.self) {
            // Above ~1973 in seconds means the host sent milliseconds.
            date = Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
            return
        }
        if let text = try? container.decode(String.self) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let parsed = iso.date(from: text) { date = parsed; return }
            iso.formatOptions = [.withInternetDateTime]
            if let parsed = iso.date(from: text) { date = parsed; return }
            date = nil
            return
        }
        date = nil
    }

    /// `14:32` for today, `10-21 14:32` otherwise; empty when the host sent nothing.
    var label: String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        let today = Calendar.current.isDateInToday(date)
        formatter.dateFormat = today ? "HH:mm" : "MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// `3m`, `2h`, `4d` — the age the team list shows beside a working Bot.
    var ageLabel: String? {
        guard let date else { return nil }
        let age = Date().timeIntervalSince(date)
        guard age >= 0 else { return nil }
        if age < 60 { return "\(Int(age))s" }
        if age < 3600 { return "\(Int(age / 60))m" }
        if age < 86_400 { return "\(Int(age / 3600))h" }
        return "\(Int(age / 86_400))d"
    }
}
