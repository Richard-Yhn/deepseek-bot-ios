// DeepSeek Bot for iOS — Apache-2.0
// One Bot's own chat. The scrollback vocabulary is grok-build-ios's (user row, agent
// block, dim centred event, hairline divider), and the prompt chrome is its PromptBar;
// what feeds them is DeepSeek Bot's `chat` endpoint.

import SwiftUI

struct BotChatView: View {
    @EnvironmentObject private var model: TeamModel

    private var theme: DSBTheme { model.theme }
    private var bot: Bot? { model.selectedBot }

    private var canSend: Bool {
        model.activeSessionId != nil && !model.team.isReadOnly
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(theme.promptBorder)
                .frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if model.chatCursor != nil {
                            olderButton
                        }
                        if model.botMessages.isEmpty {
                            emptyState
                        } else {
                            ForEach(model.botMessages) { line in
                                bubble(line.item)
                            }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("dsb-bottom")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.botMessages.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("dsb-bottom", anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo("dsb-bottom", anchor: .bottom)
                }
            }

            PromptBar(
                draft: $model.draft,
                isFocused: $model.isPromptFocused,
                modelLine: model.promptModelLine,
                theme: theme,
                placeholder: canSend ? "对 \(bot?.displayName ?? "Bot") 说点什么" : "这个 Bot 现在不能收消息",
                isEnabled: canSend
            ) {
                Task { await model.send() }
            }
        }
        .background(theme.bgBase)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                model.screen = .team
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.caption2.weight(.bold))
                    Text("团队")
                        .font(.caption.monospaced())
                }
                .foregroundStyle(theme.textSecondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(bot?.displayName ?? "Bot")
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(headerDetail)
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if model.team.isWorking(bot ?? Bot()) {
                Text("◆")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.accentAssistant)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.bgTerminal)
    }

    private var headerDetail: String {
        guard let bot else { return "" }
        if bot.waiting == true { return "还没开始 · 先在完整界面里给它选模型" }
        var pieces: [String] = []
        if let model = bot.model, !model.isEmpty { pieces.append(model) }
        if let count = bot.parts?.count, count > 1 { pieces.append("\(count) 段") }
        pieces.append("\(model.botMessages.count) 条")
        return pieces.joined(separator: " · ")
    }

    private var olderButton: some View {
        Button {
            Task { await model.loadOlder() }
        } label: {
            HStack(spacing: 6) {
                if model.isLoadingOlder {
                    ProgressView().scaleEffect(0.7).tint(theme.textSecondary)
                }
                Text(model.isLoadingOlder ? "正在往前翻…" : "更早的消息")
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textSecondary)
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .disabled(model.isLoadingOlder)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("这里还没有对话。")
                .font(.callout.monospaced())
                .foregroundStyle(theme.textSecondary)
            Text("在下面说第一句话，或者用「完整界面」看它的工具调用。")
                .font(.caption.monospaced())
                .foregroundStyle(theme.gray)
        }
        .padding(.top, 24)
        .padding(.horizontal, 4)
    }

    // MARK: - Rows

    @ViewBuilder
    private func bubble(_ item: ChatItem) -> some View {
        switch item.parsed {
        case .user:
            userRow(item)
        case .bot:
            agentRow(item)
        case .answer, .event:
            centredRow(item.placeholder, dim: true)
        case .divider:
            dividerRow(item)
        }
    }

    private func userRow(_ item: ChatItem) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Spacer(minLength: 32)
            VStack(alignment: .leading, spacing: 4) {
                if model.showTimestamps, let label = item.time?.label, !label.isEmpty {
                    Text(label)
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.gray)
                }
                Text(item.text ?? "")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bgHighlight)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(theme.accentUser.opacity(0.5))
                    .frame(width: 2)
            }
        }
    }

    private func agentRow(_ item: ChatItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Rectangle()
                .fill(theme.accentAssistant.opacity(0.6))
                .frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(bot?.displayName ?? "Bot")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(theme.accentAssistant)
                    if model.showTimestamps, let label = item.time?.label, !label.isEmpty {
                        Text(label)
                            .font(.caption2.monospaced())
                            .foregroundStyle(theme.gray)
                    }
                }
                Text(MarkdownLite.attributed(item.text ?? ""))
                    .font(.body)
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
        }
        .padding(.vertical, 2)
    }

    private func centredRow(_ text: String, dim: Bool) -> some View {
        HStack {
            Spacer(minLength: 0)
            Text(text)
                .font(.caption.monospaced())
                .foregroundStyle(dim ? theme.gray : theme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func dividerRow(_ item: ChatItem) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(theme.promptBorder).frame(height: 1)
            Text(item.time?.label ?? "分段")
                .font(.caption2.monospaced())
                .foregroundStyle(theme.gray)
            Rectangle().fill(theme.promptBorder).frame(height: 1)
        }
        .padding(.vertical, 4)
    }
}
