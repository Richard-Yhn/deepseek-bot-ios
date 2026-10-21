// DeepSeek Bot for iOS — Apache-2.0

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: TeamModel

    var body: some View {
        ZStack {
            model.theme.bgBase.ignoresSafeArea()
            content
        }
        .preferredColorScheme(model.isDark ? .dark : .light)
        .tint(model.theme.accentAssistant)
        .overlay(alignment: .top) {
            if let notice = model.notice {
                NoticeBar(text: notice, theme: model.theme) { model.clearNotice() }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.notice)
    }

    @ViewBuilder
    private var content: some View {
        switch model.screen {
        case .welcome:
            OnboardingView()
        case .team:
            TeamListView()
        case .chat:
            BotChatView()
        case .rooms:
            RoomListView()
        case .settings:
            SettingsView()
        case .web:
            WebHostView()
        }
    }
}

/// A one-line failure strip. The host's own refusal text is passed straight through —
/// `Could not reach DSH`, `bot/read-only` and friends read better than anything invented here.
struct NoticeBar: View {
    let text: String
    let theme: DSBTheme
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("!")
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(theme.accentError)
            Text(text)
                .font(.caption.monospaced())
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button(action: onClose) {
                Text("✕")
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.bgHighlight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.accentError.opacity(0.5)).frame(height: 1)
        }
    }
}
