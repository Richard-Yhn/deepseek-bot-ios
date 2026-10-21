// DeepSeek Bot for iOS — Apache-2.0
// Group chats. A room's log is not on the `chat` channel (that one pages a Bot's own
// chat), so this screen shows what `state` does carry — who is in the room, the last
// line, the approvals its members are blocked on — and hands the full room to the
// web view rather than inventing a half-fidelity transcript.

import SwiftUI

struct RoomListView: View {
    @EnvironmentObject private var model: TeamModel

    @State private var showNewRoom = false

    private var theme: DSBTheme { model.theme }
    private var rooms: [Room] { model.team.roomList }
    private var approvals: [Approval] { model.team.approvalList }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                if !approvals.isEmpty {
                    sectionTitle("成员在等确认")
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
                sectionTitle("群聊 · \(rooms.count)")
                if rooms.isEmpty {
                    Text("还没有群聊。用「完整界面」建一个，把几个 Bot 拉进去。")
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.gray)
                        .padding(16)
                } else {
                    ForEach(rooms, id: \.uid) { room in
                        row(room)
                    }
                }
                footer
            }
        }
        .refreshable { await model.refresh(force: true) }
        .background(theme.bgBase)
        .sheet(isPresented: $showNewRoom) {
            CreateRoomView()
                .environmentObject(model)
        }
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

            Text("群聊")
                .font(.body.monospaced().weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button {
                showNewRoom = true
            } label: {
                Text("新建")
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.bgTerminal)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(theme.accentAssistant)
            }
            .buttonStyle(.plain)
            Button {
                model.screen = .web
            } label: {
                Text("完整界面")
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(theme.gray)
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func row(_ room: Room) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("#")
                    .font(.body.monospaced())
                    .foregroundStyle(theme.accentAssistant)
                Text(room.displayName)
                    .font(.body.monospaced().weight(.medium))
                    .foregroundStyle(theme.textPrimary)
                if room.memberCount > 0 {
                    Text("\(room.memberCount) 人")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.gray)
                }
                Spacer()
                if let mode = room.mode, !mode.isEmpty {
                    Text(mode)
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.grayDim)
                }
            }
            if let preview = room.preview, !preview.isEmpty {
                Text(preview)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let notice = room.notice, !notice.isEmpty {
                Text(notice)
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.grayDim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.promptBorder.opacity(0.6))
                .frame(height: 1)
        }
    }

    private var footer: some View {
        Text("群聊的完整消息流在「完整界面」里，那里是 DSH 自己的 Web 客户端。")
            .font(.caption2.monospaced())
            .foregroundStyle(theme.grayDim)
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 28)
    }
}
