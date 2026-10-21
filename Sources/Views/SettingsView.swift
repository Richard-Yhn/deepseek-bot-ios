// DeepSeek Bot for iOS — Apache-2.0

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: TeamModel

    private var theme: DSBTheme { model.theme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                group("连接")
                infoRow("宿主", model.connectedHost)
                infoRow("状态", connectionText)
                if let at = model.lastRefresh {
                    infoRow("最近更新", at.formatted(date: .omitted, time: .standard))
                }
                if let readOnly = model.team.readOnly {
                    infoRow("只读原因", readOnly)
                }
                actionRow("重新核对团队", symbol: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                actionRow("打开完整界面", symbol: "safari") {
                    model.screen = .web
                }

                group("外观")
                toggleRow("深色", isOn: $model.isDark)
                toggleRow("显示时间", isOn: $model.showTimestamps)

                group("断开")
                actionRow("换一个宿主（清除已保存的地址）", symbol: "rectangle.portrait.and.arrow.right", destructive: true) {
                    model.disconnect()
                }

                group("关于")
                infoRow("版本", Bundle.main.appVersion)
                Text("""
                DeepSeek Bot for iOS 是一个客户端：Bot 团队、会话和工具都留在你机器上的 \
                DeepSeek Harness 里，手机只负责显示和发话。协议沿用官方 Web 界面的 \
                POST /api/bot，所以宿主不需要任何改动。
                """)
                .font(.caption.monospaced())
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                attribution

                Spacer(minLength: 24)
            }
        }
        .background(theme.bgBase)
    }

    private var header: some View {
        HStack(spacing: 10) {
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
            Text("设置")
                .font(.body.monospaced().weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var connectionText: String {
        switch model.connectionPhase {
        case .idle: return "未连接"
        case .checking: return "正在连接…"
        case .succeeded: return "已连接"
        case .failed(let reason): return reason
        }
    }

    private func group(_ title: String) -> some View {
        Text(title)
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(theme.gray)
            .padding(.horizontal, 12)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption.monospaced())
                .foregroundStyle(theme.gray)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func actionRow(
        _ title: String,
        symbol: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.caption)
                Text(title)
                    .font(.caption.monospaced())
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .opacity(0.5)
            }
            .foregroundStyle(destructive ? theme.accentError : theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.promptBorder.opacity(0.5)).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.caption.monospaced())
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(theme.accentAssistant)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var attribution: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("上游")
                .font(.caption2.monospaced().weight(.semibold))
                .foregroundStyle(theme.gray)
                .padding(.top, 18)
                .padding(.bottom, 2)
            link("Fei2411/DeepSeek-Bot", "https://github.com/Fei2411/DeepSeek-Bot")
            link("deepseek-ai/dsh（DeepSeek Harness）", "https://github.com/deepseek-ai/dsh")
            link("Pedroshakoor/grok-build-ios", "https://github.com/Pedroshakoor/grok-build-ios")
            Text("客户端骨架（主题、PromptBar、权限横幅、MarkdownLite）取自 grok-build-ios，Apache-2.0；协议与数据结构取自 DeepSeek-Bot。")
                .font(.caption2.monospaced())
                .foregroundStyle(theme.grayDim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .padding(.horizontal, 12)
    }

    private func link(_ title: String, _ url: String) -> some View {
        Link(destination: URL(string: url) ?? URL(string: "https://github.com")!) {
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption2)
                Text(title)
                    .font(.caption.monospaced())
                Spacer()
            }
            .foregroundStyle(theme.accentAssistant)
            .padding(.vertical, 3)
        }
    }
}

extension Bundle {
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
