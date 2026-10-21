// Derived from grok-build-ios (ios/GrokApp/GrokApp/Theme.swift)
// Copyright (c) 2026 Pedro Shakour — Apache-2.0. See NOTICE.
//
// The token names are Grok's, so a reader moving between the two clients keeps their
// bearings. The palette is DeepSeek's: the assistant accent is the DeepSeek blue that
// the whale and the web UI use, and the terminal chrome stays monospaced.

import SwiftUI

struct DSBTheme: Equatable {
    let name: String
    let isDark: Bool

    let bgTerminal: Color
    let bgBase: Color
    let bgHighlight: Color
    let bgLight: Color
    let textPrimary: Color
    let textSecondary: Color
    let gray: Color
    let grayDim: Color
    let accentUser: Color
    let accentAssistant: Color
    let accentThinking: Color
    let accentSystem: Color
    let accentError: Color
    let accentSuccess: Color
    let accentTool: Color
    let accentPlan: Color
    let command: Color
    let path: Color
    let running: Color
    let promptBorder: Color
    let promptBorderActive: Color

    static let night = DSBTheme(
        name: "DeepSeekNight",
        isDark: true,
        bgTerminal: Color(hex: "#0b0b0d"),
        bgBase: Color(hex: "#131316"),
        bgHighlight: Color(hex: "#1e1e24"),
        bgLight: Color(hex: "#26262e"),
        textPrimary: Color(hex: "#e6e6ea"),
        textSecondary: Color(hex: "#a8a8b3"),
        gray: Color(hex: "#6c6c78"),
        grayDim: Color(hex: "#55555f"),
        accentUser: Color(hex: "#c8c8d0"),
        accentAssistant: Color(hex: "#8ab4ff"),
        accentThinking: Color(hex: "#9d8cff"),
        accentSystem: Color(hex: "#7aa2f7"),
        accentError: Color(hex: "#f7768e"),
        accentSuccess: Color(hex: "#9ece6a"),
        accentTool: Color(hex: "#787888"),
        accentPlan: Color(hex: "#ffdb8d"),
        command: Color(hex: "#e0af68"),
        path: Color(hex: "#ff9e64"),
        running: Color(hex: "#7dcfff"),
        promptBorder: Color(hex: "#32323a"),
        promptBorderActive: Color(hex: "#50505c")
    )

    static let day = DSBTheme(
        name: "DeepSeekDay",
        isDark: false,
        bgTerminal: Color(hex: "#ffffff"),
        bgBase: Color(hex: "#f4f4f7"),
        bgHighlight: Color(hex: "#e8e8ee"),
        bgLight: Color(hex: "#dcdce4"),
        textPrimary: Color(hex: "#1a1a20"),
        textSecondary: Color(hex: "#5a5a66"),
        gray: Color(hex: "#8a8a96"),
        grayDim: Color(hex: "#a0a0ac"),
        accentUser: Color(hex: "#33333a"),
        accentAssistant: Color(hex: "#3d5afe"),
        accentThinking: Color(hex: "#6c4df0"),
        accentSystem: Color(hex: "#2f6fd0"),
        accentError: Color(hex: "#c62b45"),
        accentSuccess: Color(hex: "#2f7d32"),
        accentTool: Color(hex: "#7a7a88"),
        accentPlan: Color(hex: "#8a6d1f"),
        command: Color(hex: "#9a6b00"),
        path: Color(hex: "#b85c00"),
        running: Color(hex: "#0b7fa8"),
        promptBorder: Color(hex: "#d4d4dc"),
        promptBorderActive: Color(hex: "#9a9aa8")
    )

    static func named(_ name: String) -> DSBTheme {
        name.lowercased().contains("day") ? .day : .night
    }
}

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
