// DeepSeek Bot for iOS — Apache-2.0
// 建群. `create-room` takes `{ name, members[], admin?, greet? }`
// (ds-bot/src/host/channel.js). `greet: true` lets the host run the opening round as
// soon as the room exists — which is the group-chat equivalent of dispatching to
// several Bots at once.

import SwiftUI

struct CreateRoomView: View {
    @EnvironmentObject private var model: TeamModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var selected: [String] = []
    @State private var adminId: String = ""
    @State private var greet = true

    private var theme: DSBTheme { model.theme }
    private var bots: [Bot] { model.team.botList }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("新建群聊")
                        .font(.body.monospaced().weight(.semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Button("取消") { dismiss() }
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.textSecondary)
                        .buttonStyle(.plain)
                }

                Text("群名")
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.gray)
                TextField("", text: $name, prompt: Text("比如 周会"))
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textPrimary)
                    .textFieldStyle(.plain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .tint(theme.running)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 11)
                    .background(theme.bgTerminal)
                    .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))

                Text("成员 · 至少两个（\(selected.count) 已选）")
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.gray)
                VStack(spacing: 0) {
                    ForEach(bots, id: \.uid) { bot in
                        memberRow(bot)
                    }
                }

                if selected.count >= 2 {
                    Text("管理员")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.gray)
                    Picker("管理员", selection: $adminId) {
                        Text("不指定").tag("")
                        ForEach(bots.filter { selected.contains($0.uid) }, id: \.uid) { bot in
                            Text(bot.displayName).tag(bot.uid)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(theme.accentAssistant)
                }

                Toggle(isOn: $greet) {
                    Text("建好后让成员先互相打个招呼")
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.textSecondary)
                }
                .tint(theme.accentAssistant)

                Button {
                    Task { await create() }
                } label: {
                    HStack(spacing: 8) {
                        if model.isBusy { ProgressView().scaleEffect(0.8).tint(theme.bgTerminal) }
                        Text("建这个群")
                            .font(.body.monospaced().weight(.semibold))
                        Spacer()
                    }
                    .foregroundStyle(theme.bgTerminal)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .background(canCreate ? theme.accentAssistant : theme.grayDim)
                }
                .buttonStyle(.plain)
                .disabled(!canCreate || model.isBusy)

                Spacer(minLength: 20)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.bgBase)
    }

    private func memberRow(_ bot: Bot) -> some View {
        let isOn = selected.contains(bot.uid)
        return Button {
            if isOn {
                selected.removeAll { $0 == bot.uid }
                if adminId == bot.uid { adminId = "" }
            } else {
                selected.append(bot.uid)
            }
        } label: {
            HStack(spacing: 8) {
                Text(isOn ? "[x]" : "[ ]")
                    .font(.body.monospaced())
                    .foregroundStyle(isOn ? theme.accentAssistant : theme.gray)
                Circle().fill(BotInk.color(bot.color)).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bot.displayName)
                        .font(.body.monospaced())
                        .foregroundStyle(theme.textPrimary)
                    Text(bot.model?.isEmpty == false ? bot.model! : "默认模型")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.gray)
                }
                Spacer()
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.promptBorder.opacity(0.5)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selected.count >= 2
    }

    private func create() async {
        let ok = await model.createRoom(
            name: name,
            members: selected,
            admin: adminId.isEmpty ? nil : adminId,
            greet: greet
        )
        if ok { dismiss() }
    }
}
