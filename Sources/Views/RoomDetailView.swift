// DeepSeek Bot for iOS — Apache-2.0
// One group chat, as far as `/api/bot` reaches.
//
// Sending works: a room is a Session, and the official client posts with `room.id`
//   (client/new-chat.js:75  →  actions.send(room.id, text)
//    team-actions.js:69     →  call('send', { sessionId: partFor(id), text }))
// Live progress works: `room-progress { roomId }` → [{ callId, replies, speaking }].
// Approvals work: `approval-answer`, and `stop-member-work` to end a member's turn.
//
// The transcript does not: `view()` destructures each room's `log` away and keeps only
// `preview`, while `chat`/`earlier` require `botOf(sessionId)` — never true for a room
// id. The desktop window shows it because it lives inside DSH's own web client. So the
// last line and the live strip are here, and the full log is one tap away.

import SwiftUI

struct RoomDetailView: View {
    @EnvironmentObject private var model: TeamModel

    private var theme: DSBTheme { model.theme }
    private var room: Room? { model.selectedRoom }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(theme.promptBorder).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let room {
                        liveStrip(room)
                        memberList(room)
                        approvals
                        lastLine(room)
                        explainer
                    } else {
                        Text("这个群聊已经不在了。")
                            .font(.caption.monospaced())
                            .foregroundStyle(theme.gray)
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            PromptBar(
                draft: $model.roomDraft,
                isFocused: $model.isPromptFocused,
                modelLine: modelLine,
                theme: theme,
                placeholder: canSend ? "在群里说一句" : "这个宿主只能读，不能发消息",
                isEnabled: canSend
            ) {
                Task { await model.sendToRoom() }
            }
        }
        .background(theme.bgBase)
        .task { await model.loadRoomProgress() }
    }

    private var canSend: Bool {
        model.selectedRoom?.id != nil && !model.team.isReadOnly
    }

    private var modelLine: String {
        guard let room = room else { return "" }
        var pieces = ["#\(room.displayName)"]
        pieces.append("\(room.memberCount) 人")
        if let mode = room.mode, !mode.isEmpty { pieces.append(mode) }
        if model.isRoomRunning { pieces.append("有人在说") }
        if model.team.isReadOnly { pieces.append("只读") }
        return pieces.joined(separator: " · ")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                model.screen = .rooms
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.caption2.weight(.bold))
                    Text("群聊").font(.caption.monospaced())
                }
                .foregroundStyle(theme.textSecondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(room?.displayName ?? "群聊")
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(room.map { "\($0.memberCount) 个成员" } ?? "")
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.gray)
            }
            Spacer()
            Button {
                model.screen = .web
            } label: {
                Text("完整消息流")
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.bgTerminal)
    }

    private func liveStrip(_ room: Room) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(model.isRoomRunning ? theme.running : theme.gray)
                    .frame(width: 6, height: 6)
                Text(model.isRoomRunning ? "这一轮在跑" : "空闲")
                    .font(.caption.monospaced())
                    .foregroundStyle(model.isRoomRunning ? theme.running : theme.gray)
                Spacer()
                if !model.roomProgress.isEmpty {
                    Text("\(model.roomProgress.count) 个调用在跑")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.gray)
                }
            }
            ForEach(model.roomProgress) { entry in
                HStack(spacing: 6) {
                    Text("·")
                        .foregroundStyle(theme.grayDim)
                    Text(speakerName(entry.speaking))
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.textSecondary)
                    if let replies = entry.replies, replies > 0 {
                        Text("已回 \(replies) 条")
                            .font(.caption2.monospaced())
                            .foregroundStyle(theme.gray)
                    }
                    Spacer()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgHighlight)
    }

    private func speakerName(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "某个成员" }
        if let bot = model.team.bot(raw) { return bot.displayName }
        return raw
    }

    private func memberList(_ room: Room) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("成员")
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(theme.gray)
                .padding(.bottom, 6)
            ForEach(model.members(of: room), id: \.uid) { bot in
                HStack(spacing: 8) {
                    Circle().fill(BotInk.color(bot.color)).frame(width: 7, height: 7)
                    Text(bot.displayName)
                        .font(.body.monospaced())
                        .foregroundStyle(theme.textPrimary)
                    if model.team.isWorking(bot) {
                        Text("◆")
                            .font(.caption2.monospaced())
                            .foregroundStyle(theme.accentAssistant)
                        Button("停") {
                            guard let botId = bot.id else { return }
                            Task { await model.stopMember(in: room, botId: botId) }
                        }
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.accentError)
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Text(bot.model?.isEmpty == false ? bot.model! : "默认模型")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.gray)
                        .lineLimit(1)
                }
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.promptBorder.opacity(0.5)).frame(height: 1)
                }
            }
            if let admin = room.admin, let bot = model.team.bot(admin) {
                Text("管理员：\(bot.displayName)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.grayDim)
                    .padding(.top, 6)
            }
        }
    }

    private var pendingApprovals: [Approval] {
        model.team.approvalList.filter { $0.roomId == room?.id }
    }

    @ViewBuilder
    private var approvals: some View {
        if !pendingApprovals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("成员在等确认")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(theme.command)
                ForEach(pendingApprovals, id: \.uid) { approval in
                    PermissionBanner(
                        request: model.permissionRequest(for: approval),
                        theme: theme
                    ) { choice in
                        Task { await model.answer(approval, choice: choice) }
                    }
                }
            }
        }
    }

    private func lastLine(_ room: Room) -> some View {
        Group {
            if let preview = room.preview, !preview.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最后一句")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.gray)
                    Text(preview)
                        .font(.body.monospaced())
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.bgTerminal)
                .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
            }
        }
    }

    private var explainer: some View {
        Text("""
        群聊的完整消息流不在这条客户端通道上：宿主把每个房间的 log 从 state 里摘掉了\
        （只留最后一句），chat / earlier 也只认 Bot 自己的会话。这里保留的是能拿到的\
        全部——发消息、谁在说、几次调用、待确认的工具审批。看完整记录点右上角。
        """)
        .font(.caption2.monospaced())
        .foregroundStyle(theme.grayDim)
        .fixedSize(horizontal: false, vertical: true)
    }
}
