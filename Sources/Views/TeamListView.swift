// DeepSeek Bot for iOS — Apache-2.0
// The team, drawn the way grok-build-ios draws its dashboard: a filled diamond for a
// Bot holding a turn, a hollow one for an idle Bot, the age on the right. Rows that
// need a person (approvals) sit above the roster, because a phone is mostly opened
// to unblock something.
//
// Every row shows the model that Bot runs on, because a team of Bots on one model is a
// team of one voice: the point of per-Bot model refs is that they differ.

import SwiftUI

struct TeamListView: View {
    @EnvironmentObject private var model: TeamModel

    @State private var manage: ManageTarget?

    private var theme: DSBTheme { model.theme }
    private var approvals: [Approval] { model.team.approvalList }
    private var bots: [Bot] { model.team.botList }
    private var working: Int { bots.filter { model.team.isWorking($0) }.count }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                if !approvals.isEmpty {
                    sectionTitle("需要你确认 · \(approvals.count)")
                    ForEach(approvals, id: \.uid) { approval in
                        PermissionBanner(
                            request: model.permissionRequest(for: approval),
                            theme: theme
                        ) { choice in
                            Task { await model.answer(approval, choice: choice) }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                    }
                }
                sectionTitle("Bot · \(bots.count)" + (working > 0 ? " · \(working) 个在跑" : ""))
                if bots.isEmpty {
                    empty
                } else {
                    ForEach(bots, id: \.uid) { bot in
                        row(bot)
                        Rectangle()
                            .fill(theme.promptBorder.opacity(0.6))
                            .frame(height: 1)
                            .padding(.leading, 44)
                    }
                }
                footer
            }
        }
        .refreshable { await model.refresh(force: true) }
        .safeAreaInset(edge: .bottom) { actionBar }
        .background(theme.bgBase)
        .sheet(item: $manage) { target in
            ManageBotView(bot: target.bot)
                .environmentObject(model)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Bot 团队")
                    .font(.title3.monospaced().weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Button {
                    manage = ManageTarget(bot: nil)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus").font(.caption2.weight(.bold))
                        Text("新建").font(.caption2.monospaced())
                    }
                    .foregroundStyle(theme.bgTerminal)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(theme.accentAssistant)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusLine)
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                if model.team.isReadOnly {
                    Text("只读")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.accentPlan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(Rectangle().stroke(theme.accentPlan, lineWidth: 1))
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var statusColor: Color {
        switch model.connectionPhase {
        case .succeeded: return theme.accentSuccess
        case .checking: return theme.running
        case .failed: return theme.accentError
        case .idle: return theme.gray
        }
    }

    private var statusLine: String {
        switch model.connectionPhase {
        case .checking:
            return "正在连接 \(model.connectedHost)…"
        case .failed(let reason):
            return reason
        case .idle:
            return "未连接"
        case .succeeded:
            var pieces = [model.connectedHost]
            if let at = model.lastRefresh {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss"
                pieces.append("更新于 \(formatter.string(from: at))")
            }
            if model.team.isReadOnly { pieces.append("另一台 dsh 占着这支团队") }
            return pieces.joined(separator: " · ")
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(theme.gray)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func row(_ bot: Bot) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                Task { await model.openBot(bot) }
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text(model.team.isWorking(bot) ? "◆" : "◇")
                        .font(.body.monospaced())
                        .foregroundStyle(model.team.isWorking(bot) ? theme.accentAssistant : theme.gray)
                        .frame(width: 22, alignment: .leading)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(bot.displayName)
                                .font(.body.monospaced().weight(.medium))
                                .foregroundStyle(theme.textPrimary)
                            if model.team.isMain(bot) {
                                Text("主")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(theme.bgTerminal)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(theme.accentAssistant)
                            }
                            if bot.waiting == true {
                                Text("等选模型")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(theme.accentPlan)
                            }
                        }
                        Text(modelLine(bot))
                            .font(.caption2.monospaced())
                            .foregroundStyle(
                                model.team.isCustomModel(bot.model) ? theme.accentSuccess : theme.textSecondary
                            )
                            .lineLimit(1)
                        Text(botStatus(bot))
                            .font(.caption2.monospaced())
                            .foregroundStyle(theme.gray)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                manage = ManageTarget(bot: bot)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption2)
                    .foregroundStyle(theme.gray)
                    .padding(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    /// `provider/model` → the model name, with the role beside it.
    private func modelLine(_ bot: Bot) -> String {
        var short = "默认模型"
        if let ref = bot.model, !ref.isEmpty {
            if let slash = ref.firstIndex(of: "/") {
                short = String(ref[ref.index(after: slash)...])
            } else {
                short = ref
            }
        }
        let task: String
        if let role = bot.role, !role.isEmpty {
            task = role
        } else if let brief = bot.brief, !brief.isEmpty {
            task = brief
        } else {
            task = ""
        }
        return task.isEmpty ? short : "\(short) · \(task)"
    }

    private func botStatus(_ bot: Bot) -> String {
        if bot.waiting == true { return "还没开始，先给它挑个模型" }
        if model.team.isWorking(bot) {
            if let id = bot.id, let age = model.team.work?.turns?[id]?.ageLabel {
                return "正在干活 · \(age)"
            }
            return "正在干活"
        }
        if let count = bot.parts?.count, count > 1 { return "\(count) 段对话" }
        if let sessionId = bot.sessionId, model.team.questions?[sessionId] != nil {
            return "在等你回答问题"
        }
        return "空闲"
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("这支团队里还没有 Bot。")
                .font(.callout.monospaced())
                .foregroundStyle(theme.textSecondary)
            Text("点右上角「新建」，给它起名字、选模型、写任务。")
                .font(.caption.monospaced())
                .foregroundStyle(theme.gray)
        }
        .padding(16)
    }

    private var footer: some View {
        Text("干活时每 1–4 秒增量核对一次团队 · 下拉可立即全量刷新")
            .font(.caption2.monospaced())
            .foregroundStyle(theme.grayDim)
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 12)
    }

    private var actionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("派活", symbol: "paperplane") { model.screen = .dispatch }
                chip("群聊", symbol: "bubble.left.and.bubble.right") { model.screen = .rooms }
                chip("供应商", symbol: "server.rack") { model.screen = .providers }
                chip("直连模型", symbol: "cpu") { model.screen = .direct }
                chip("完整界面", symbol: "safari") { model.screen = .web }
                chip("设置", symbol: "gearshape") { model.screen = .settings }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(theme.bgTerminal)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.promptBorder).frame(height: 1)
        }
    }

    private func chip(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.caption2)
                Text(title).font(.caption2.monospaced())
            }
            .foregroundStyle(theme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
