// DeepSeek Bot for iOS — Apache-2.0
// `state.colors` is a list of ink *names*, not hex (ds-bot/src/host/constants.js):
//   COLORS       = deepseek, blue, violet, orange, green, magenta, cyan, red,
//                  yellow, brown, gray, black, aurora
//   EXTRA_COLORS = charcoal, graphite, rose, sky, tangerine, cobalt
// The host stores whichever name the user picked, so this app maps names to swatches
// and sends the name back — never a colour of its own invention.

import SwiftUI

enum BotInk {
    /// Every ink the host offers, in the order it offers them.
    static let names: [String] = [
        "deepseek", "blue", "violet", "orange", "green", "magenta", "cyan", "red",
        "yellow", "brown", "gray", "black", "aurora",
        "charcoal", "graphite", "rose", "sky", "tangerine", "cobalt",
    ]

    private static let hexes: [String: String] = [
        "deepseek": "#4d6bfe",
        "blue": "#3b82f6",
        "violet": "#8b5cf6",
        "orange": "#f97316",
        "green": "#22c55e",
        "magenta": "#d946ef",
        "cyan": "#06b6d4",
        "red": "#ef4444",
        "yellow": "#eab308",
        "brown": "#a16207",
        "gray": "#6b7280",
        "black": "#1f2937",
        "aurora": "#2dd4bf",
        "charcoal": "#374151",
        "graphite": "#4b5563",
        "rose": "#f43f5e",
        "sky": "#0ea5e9",
        "tangerine": "#ff8a3d",
        "cobalt": "#1d4ed8",
    ]

    /// The swatch for an ink name. Unknown names (a future release, a legacy id) still
    /// get a stable colour, so a row never loses its dot.
    static func color(_ name: String?) -> Color {
        guard let name, !name.isEmpty else { return Color(hex: "#6b7280") }
        if let hex = hexes[name.lowercased()] { return Color(hex: hex) }
        if name.hasPrefix("#") { return Color(hex: name) }
        var hash: UInt64 = 5381
        for scalar in name.unicodeScalars {
            hash = (hash &* 33) &+ UInt64(scalar.value)
        }
        let palette = Array(hexes.values).sorted()
        return Color(hex: palette[Int(hash % UInt64(palette.count))])
    }

    static func isKnown(_ name: String) -> Bool {
        hexes[name.lowercased()] != nil
    }
}
