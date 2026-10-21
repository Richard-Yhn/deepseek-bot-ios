// DeepSeek Bot for iOS — Apache-2.0
// 派活: one job, several Bots, different angles, at the same time.
//
// Each Bot on the host is its own root Session, so this screen is just N `send` calls —
// the host runs the N turns in parallel. The per-Bot note is the part that makes it
// useful: five Bots on one review, each told which slice to look at, instead of five
// identical answers.

import SwiftUI

struct DispatchView: View {
    @EnvironmentObject private var model: TeamModel

    @State private var task: String = ""
    @State private var targets: [DispatchTarget] = []
    @State private var result: String?
    @State private var isSending = false

    private var theme: DSBTheme { model.theme }
    private var selectedCount: Int { targets.filter(\.selected).count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(theme.promptBorder).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    taskBlock
                    rosterBlock
                    if let result {
                        Text(result)
                            .font(.caption.monospaced())
                            .foregroundStyle(theme.accentSuccess)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
            sendBar
        }
        .background(theme.bgBase)
        .task { syncTargets() }
        .onChange(of: model.team.botList.count) { _, _ in syncTargets() }
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
                Text("派活")
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("同一件事，分给几个 Bot 同时做")
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.gray)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.bgTerminal)
    }

    private var taskBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("这次要做什么")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(theme.textSecondary)
            TextEditor(text: $task)
                .font(.body.monospaced())
                .foregroundStyle(theme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(8)
                .background(theme.bgTerminal)
                .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
            Text("每个 Bot 收到的是同一段话，再加上你在它那一行写的重点。")
                .font(.caption2.monospaced())
                .foregroundStyle(theme.grayDim)
        }
    }

    private var rosterBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("分给谁 · \(selectedCount)/\(targets.count)")
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button(selectedCount == targets.count ? "全不选" : "全选") {
                    let selectAll = selectedCount != targets.count
                    for index in targets.indices { targets[index].selected = selectAll }
                }
                .font(.caption.monospaced())
                .foregroundStyle(theme.accentAssistant)
                .buttonStyle(.plain)
            }

            if targets.isEmpty {
                Text("团队里还没有 Bot。先在团队列表右上角新建一个。")
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.gray)
            }

            ForEach($targets) { $target in
                targetRow($target)
            }
        }
    }

    private func targetRow(_ target: Binding<DispatchTarget>) -> some View {
        let bot = target.wrappedValue.bot
        let working = model.team.isWorking(bot)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    target.wrappedValue.selected.toggle()
                } label: {
                    Text(target.wrappedValue.selected ? "[x]" : "[ ]")
                        .font(.body.monospaced())
                        .foregroundStyle(target.wrappedValue.selected ? theme.accentAssistant : theme.gray)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(BotInk.color(bot.color))
                            .frame(width: 7, height: 7)
                        Text(bot.displayName)
                            .font(.body.monospaced())
                            .foregroundStyle(theme.textPrimary)
                        if working {
                            Text("跑着")
                                .font(.caption2.monospaced())
                                .foregroundStyle(theme.running)
                        }
                    }
                    Text("\(target.wrappedValue.modelLabel) · \(bot.role?.isEmpty == false ? bot.role! : "没写角色")")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.gray)
                        .lineLimit(1)
                    if let brief = bot.brief, !brief.isEmpty {
                        Text(brief)
                            .font(.caption2.monospaced())
                            .foregroundStyle(theme.grayDim)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            if target.wrappedValue.selected {
                TextField("", text: target.note, prompt: Text("你这一份的重点（可留空）"))
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textPrimary)
                    .textFieldStyle(.plain)
                    .tint(theme.running)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                    .background(theme.bgHighlight)
                    .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
                    .padding(.leading, 26)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.promptBorder.opacity(0.5)).frame(height: 1)
        }
    }

    private var sendBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.promptBorder).frame(height: 1)
            Button {
                Task {
                    isSending = true
                    result = await model.dispatch(task, targets: targets)
                    isSending = false
                    await model.refresh(force: true)
                }
            } label: {
                HStack(spacing: 8) {
                    if isSending { ProgressView().scaleEffect(0.8).tint(theme.bgTerminal) }
                    Text(isSending ? "正在派…" : "派给 \(selectedCount) 个 Bot")
                        .font(.body.monospaced().weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(theme.bgTerminal)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(canSend ? theme.accentAssistant : theme.grayDim)
            }
            .buttonStyle(.plain)
            .disabled(!canSend || isSending)
            .padding(12)
            .background(theme.bgTerminal)
        }
    }

    private var canSend: Bool {
        selectedCount > 0 && !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func syncTargets() {
        var previous: [String: DispatchTarget] = [:]
        for target in targets { previous[target.id] = target }
        var next: [DispatchTarget] = []
        for bot in model.team.botList {
            if var kept = previous[bot.uid] {
                kept.bot = bot
                next.append(kept)
            } else {
                next.append(DispatchTarget(bot: bot))
            }
        }
        targets = next
    }
}
