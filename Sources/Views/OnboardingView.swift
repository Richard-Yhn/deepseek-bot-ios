// DeepSeek Bot for iOS — Apache-2.0
// The connect screen, in the layout of grok-build-ios's OnboardingView: what you paste
// at the top, one verb under it, the caveats in small type below. Grok asks for a host,
// a port and a pairing secret; DeepSeek Bot asks for the login URL that `dsh web` prints,
// because that single line already carries the authority and the token.

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: TeamModel

    private enum Field: Hashable {
        case host
        case token
    }

    @FocusState private var focused: Field?

    private var isBusy: Bool { model.connectionPhase == .checking }
    private var canSubmit: Bool { !model.loginDraft.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                fields
                submit
                if let error = model.setupError, !error.isEmpty {
                    Text(error)
                        .font(.caption.monospaced())
                        .foregroundStyle(model.theme.accentError)
                        .fixedSize(horizontal: false, vertical: true)
                }
                howTo
                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(model.theme.bgBase)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "fish.fill")
                    .font(.title2)
                    .foregroundStyle(model.theme.accentAssistant)
                Text("DeepSeek Bot")
                    .font(.title2.monospaced().weight(.semibold))
                    .foregroundStyle(model.theme.textPrimary)
            }
            Text("一队长期活着的 Bot，跑在你自己的机器上。手机既是遥控器，也是一份算力。")
                .font(.callout.monospaced())
                .foregroundStyle(model.theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            fieldRow(title: "宿主地址", prompt: "192.168.1.5:3080") {
                TextField("", text: $model.loginDraft, prompt: Text("192.168.1.5:3080"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focused, equals: .host)
                    .submitLabel(.next)
                    .onSubmit { focused = .token }
            }
            fieldRow(title: "令牌（地址里已带 ?token= 时可留空）", prompt: "token") {
                TextField("", text: $model.tokenDraft, prompt: Text("token"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .token)
                    .submitLabel(.go)
                    .onSubmit { submitIfPossible() }
            }
        }
    }

    private func fieldRow<Content: View>(
        title: String,
        prompt: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.monospaced())
                .foregroundStyle(model.theme.gray)
            HStack(spacing: 8) {
                Text("❯")
                    .font(.body.monospaced())
                    .foregroundStyle(model.theme.accentAssistant)
                content()
                    .font(.body.monospaced())
                    .foregroundStyle(model.theme.textPrimary)
                    .textFieldStyle(.plain)
                    .tint(model.theme.running)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(model.theme.bgTerminal)
            .overlay(
                Rectangle()
                    .stroke(model.theme.promptBorder, lineWidth: 1)
            )
        }
    }

    private var submit: some View {
        Button {
            submitIfPossible()
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .tint(model.theme.bgTerminal)
                        .scaleEffect(0.8)
                }
                Text(isBusy ? "正在连接…" : "连接宿主")
                    .font(.body.monospaced().weight(.semibold))
                Spacer()
                Text("[↵]")
                    .font(.caption.monospaced())
                    .opacity(0.7)
            }
            .foregroundStyle(model.theme.bgTerminal)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(canSubmit ? model.theme.accentAssistant : model.theme.grayDim)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || isBusy)
    }

    private var howTo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("怎么拿到这个地址")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(model.theme.textSecondary)
            hint("1", "电脑上装好 DeepSeek Bot：桌面版直接打开；服务器上用 npx @deepseek-ai/dsh@0.2.1-rc.2 plugin --profile web add ds-bot 再 dsh web。")
            hint("2", "启动后终端会打印一行 dsh web: http://127.0.0.1:3080/?token=… —— 把 127.0.0.1 换成这台电脑的局域网 IP。")
            hint("3", "手机和电脑连同一个 Wi-Fi，把那一行整条粘到上面。第一次连接会请求「本地网络」权限，必须允许。")
        }
        .padding(12)
        .background(model.theme.bgHighlight)
    }

    private func hint(_ index: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(index)
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(model.theme.accentAssistant)
            Text(text)
                .font(.caption.monospaced())
                .foregroundStyle(model.theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DeepSeek Harness 之上的 ds-bot 团队 · 客户端协议与官方 Web 界面同一套 POST /api/bot")
                .font(.caption2.monospaced())
                .foregroundStyle(model.theme.gray)
            Text("开源 · Apache-2.0 · 客户端骨架取自 grok-build-ios")
                .font(.caption2.monospaced())
                .foregroundStyle(model.theme.grayDim)
        }
    }

    private func submitIfPossible() {
        guard canSubmit, !isBusy else { return }
        focused = nil
        Task { await model.connectFromDraft() }
    }
}
