// DeepSeek Bot for iOS — Apache-2.0
// 手机直连模型. The phone holds its own conversation against any OpenAI-compatible
// endpoint — no host, no LAN, no desktop. Anything worth keeping can then be handed to
// a Bot on the host, which is what makes this "compute" rather than a second notebook.

import SwiftUI

struct DirectChatView: View {
    @EnvironmentObject private var model: TeamModel

    @State private var config = DirectStore.loadConfig()
    @State private var messages = DirectStore.loadMessages()
    @State private var draft = ""
    @State private var isStreaming = false
    @State private var errorText: String?
    @State private var showConfig = false
    @State private var handoffText: String?
    @State private var showHandoff = false

    private var theme: DSBTheme { model.theme }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(theme.promptBorder).frame(height: 1)
            if showConfig { configPanel }
            conversation
            if let errorText {
                Text(errorText)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.accentError)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(theme.bgHighlight)
            }
            PromptBar(
                draft: $draft,
                isFocused: .constant(false),
                modelLine: modelLine,
                theme: theme,
                placeholder: config.isUsable ? "直接问这个模型" : "先点右上角配置接口",
                isEnabled: !isStreaming
            ) {
                send()
            }
        }
        .background(theme.bgBase)
        .sheet(isPresented: $showHandoff) {
            handoffSheet
        }
    }

    private var modelLine: String {
        var pieces: [String] = []
        pieces.append(config.model.isEmpty ? "未配置模型" : config.model)
        if let host = URL(string: config.baseURL)?.host { pieces.append(host) }
        pieces.append("手机直连 · 不走宿主")
        return pieces.joined(separator: " · ")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                model.screen = .team
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.caption2.weight(.bold))
                    Text("团队").font(.caption.monospaced())
                }
                .foregroundStyle(theme.textSecondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text("直连模型")
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("手机自己的算力")
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.gray)
            }
            Spacer()
            Button {
                showConfig.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .padding(8)
                    .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.bgTerminal)
    }

    private var configPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("接口地址 · 到 /v1 为止")
            field {
                TextField("", text: $config.baseURL, prompt: Text("https://api.deepseek.com/v1"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            label("模型名")
            field {
                TextField("", text: $config.model, prompt: Text("deepseek-chat"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            label("API Key")
            SecureKeyField(placeholder: "sk-…", theme: theme) { value in
                config.apiKey = value
                DirectStore.saveConfig(config)
            }
            label("系统提示（可选）")
            field {
                TextField("", text: $config.systemPrompt, prompt: Text("你是一个简洁的助手"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            HStack(spacing: 14) {
                Button("保存") {
                    DirectStore.saveConfig(config)
                    showConfig = false
                }
                .font(.caption.monospaced())
                .foregroundStyle(theme.accentAssistant)
                .buttonStyle(.plain)
                Button("清空对话") {
                    messages = []
                    DirectStore.clearMessages()
                }
                .font(.caption.monospaced())
                .foregroundStyle(theme.accentError)
                .buttonStyle(.plain)
                Spacer()
            }
            Text("密钥只存在这台手机上，直接发给上面这个地址，不经过宿主。")
                .font(.caption2.monospaced())
                .foregroundStyle(theme.grayDim)
        }
        .padding(12)
        .background(theme.bgHighlight)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        Text("这里不连宿主：填一个接口，手机就能自己算。\n说到值得留下的结论，点旁边的「交给团队」发给某个 Bot。")
                            .font(.caption.monospaced())
                            .foregroundStyle(theme.gray)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 20)
                    }
                    ForEach(messages) { message in
                        row(message)
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("direct-bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("direct-bottom", anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ message: DirectMessage) -> some View {
        if message.isUser {
            HStack {
                Spacer(minLength: 32)
                Text(message.text)
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .background(theme.bgHighlight)
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(config.model.isEmpty ? "模型" : config.model)
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.accentAssistant)
                    Spacer()
                    if !message.text.isEmpty && !isStreaming {
                        Button("交给团队") {
                            handoffText = message.text
                            showHandoff = true
                        }
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.textSecondary)
                        .buttonStyle(.plain)
                    }
                }
                Text(MarkdownLite.attributed(message.text.isEmpty ? "…" : message.text))
                    .font(.body)
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
    }

    private var handoffSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("交给哪个 Bot")
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.bottom, 10)
                ForEach(model.team.botList, id: \.uid) { bot in
                    Button {
                        handoff(to: bot)
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(BotInk.color(bot.color)).frame(width: 7, height: 7)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bot.displayName)
                                    .font(.body.monospaced())
                                    .foregroundStyle(theme.textPrimary)
                                Text(bot.model?.isEmpty == false ? bot.model! : "默认模型")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(theme.gray)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(theme.promptBorder.opacity(0.5)).frame(height: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if model.team.botList.isEmpty {
                    Text("宿主上还没有 Bot。")
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.gray)
                        .padding(.top, 12)
                }
            }
            .padding(16)
        }
        .background(theme.bgBase)
    }

    private func handoff(to bot: Bot) {
        guard let text = handoffText else { return }
        showHandoff = false
        var target = DispatchTarget(bot: bot)
        target.selected = true
        Task {
            let summary = await model.dispatch(
                "下面是一段在手机上直接和模型聊出来的结论，接下来由你接手：\n\n\(text)",
                targets: [target]
            )
            model.notice = summary
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard config.isUsable else {
            showConfig = true
            errorText = "先填接口地址和模型名。"
            return
        }
        errorText = nil
        let answerId = UUID().uuidString
        messages.append(DirectMessage(role: "user", text: text))
        messages.append(DirectMessage(id: answerId, role: "assistant", text: ""))
        let history = Array(messages.dropLast())
        draft = ""
        isStreaming = true
        Task {
            do {
                try await DirectModel.stream(config: config, history: history) { delta in
                    if let index = messages.firstIndex(where: { $0.id == answerId }) {
                        messages[index].text += delta
                    }
                }
            } catch {
                errorText = error.localizedDescription
                if let index = messages.firstIndex(where: { $0.id == answerId }),
                   messages[index].text.isEmpty {
                    messages.remove(at: index)
                }
            }
            isStreaming = false
            DirectStore.saveMessages(messages)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(theme.gray)
    }

    private func field<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.body.monospaced())
            .foregroundStyle(theme.textPrimary)
            .textFieldStyle(.plain)
            .tint(theme.running)
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .background(theme.bgTerminal)
            .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
    }
}
