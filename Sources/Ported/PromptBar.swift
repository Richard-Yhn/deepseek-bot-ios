// Derived from grok-build-ios (ios/GrokApp/GrokApp/Views/PromptBar.swift)
// Copyright (c) 2026 Pedro Shakour — Apache-2.0. See NOTICE.
//
// Same chrome as Grok's prompt widget: prompt line, `[send]` on the right (a phone
// has no Enter key), model line underneath. Here the model line reports the Bot's
// own model and whether the team is read-only, instead of Grok's plan mode.

import SwiftUI

struct PromptBar: View {
    @Binding var draft: String
    @Binding var isFocused: Bool
    let modelLine: String
    let theme: DSBTheme
    let placeholder: String
    let isEnabled: Bool
    let onSend: () -> Void

    @FocusState private var fieldFocused: Bool
    private let promptFont = Font.body.monospaced()

    private var canSend: Bool {
        isEnabled && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(fieldFocused ? theme.promptBorderActive : theme.promptBorder)
                .frame(height: 1)

            HStack(alignment: .center, spacing: 8) {
                Text("❯")
                    .font(promptFont)
                    .foregroundStyle(isEnabled ? theme.accentAssistant : theme.gray)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: focusPrompt)

                ZStack(alignment: .leading) {
                    if draft.isEmpty {
                        Text(placeholder)
                            .font(promptFont)
                            .foregroundStyle(theme.textSecondary.opacity(0.55))
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $draft, axis: .vertical)
                        .font(promptFont)
                        .foregroundStyle(theme.textPrimary)
                        .tint(theme.running)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .focused($fieldFocused)
                        .submitLabel(.send)
                        .onSubmit { if canSend { onSend() } }
                        .disabled(!isEnabled)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)

                Button(action: onSend) {
                    Text("[send]")
                        .font(.caption.monospaced())
                        .foregroundStyle(canSend ? theme.accentAssistant : theme.textSecondary.opacity(0.45))
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(theme.bgTerminal)

            Rectangle()
                .fill(theme.promptBorder)
                .frame(height: 1)

            HStack {
                Text(modelLine.isEmpty ? " " : modelLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(theme.bgTerminal)
        }
        .onChange(of: fieldFocused) { _, focused in
            isFocused = focused
        }
    }

    private func focusPrompt() {
        guard isEnabled else { return }
        fieldFocused = false
        DispatchQueue.main.async {
            fieldFocused = true
            isFocused = true
        }
    }
}
