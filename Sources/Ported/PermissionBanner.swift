// Derived from grok-build-ios (ios/GrokApp/GrokApp/Views/PermissionBanner.swift)
// Copyright (c) 2026 Pedro Shakour — Apache-2.0. See NOTICE.
//
// Grok answers ACP `session/request_permission` here; DeepSeek Bot answers
// `approval-answer {id, choice}` (choice is exactly `allow` or `reject` —
// ds-bot/src/host/approvals.js OUTCOMES). Numbered radio rows, same as upstream.

import SwiftUI

struct PermissionBanner: View {
    let request: PermissionRequest
    let theme: DSBTheme
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = request.title, !title.isEmpty {
                Text(title)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.gray)
            }
            Text(request.message)
                .font(.body.weight(.semibold).monospaced())
                .foregroundStyle(theme.command)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(request.options.enumerated()), id: \.element.id) { index, option in
                    optionRow(index: index + 1, option: option)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgHighlight)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.command)
                .frame(width: 2)
        }
    }

    private func optionRow(index: Int, option: PermissionOption) -> some View {
        let selected = option.optionId == request.selectedOptionId
        return Button {
            onSelect(option.optionId)
        } label: {
            HStack(spacing: 8) {
                Text("\(index) ")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.accentAssistant)
                Text(selected ? "(●)" : "(○)")
                    .font(.body.monospaced())
                    .foregroundStyle(selected ? theme.textPrimary : theme.gray)
                Text(option.name)
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textPrimary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
