// DeepSeek Bot for iOS — Apache-2.0
// The escape hatch. Everything the native screens do not draw — room transcripts, tool
// calls, memory panels, provider keys, capability settings — is still the host's own
// web client, so it is one tap away instead of missing.
//
// It loads the same login URL the phone used to connect, which means it sets its own
// signed cookie in WKWebView's store: no cookie hand-off between URLSession and WebKit
// to get wrong.

import SwiftUI
import WebKit

struct WebHostView: View {
    @EnvironmentObject private var model: TeamModel
    @State private var reloadToken = 0

    private var theme: DSBTheme { model.theme }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(theme.promptBorder)
                .frame(height: 1)
            if let url = model.loginURL {
                WebCanvas(url: url)
                    .id(reloadToken)
            } else {
                VStack(spacing: 8) {
                    Text("还没有连接宿主。")
                        .font(.body.monospaced())
                        .foregroundStyle(theme.textSecondary)
                    Text("回到连接页填上 dsh 打印的地址。")
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            Text("完整界面")
                .font(.body.monospaced().weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer()

            Button {
                reloadToken += 1
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .padding(8)
                    .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)

            if let url = model.loginURL {
                Link(destination: url) {
                    Image(systemName: "safari")
                        .font(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .padding(8)
                        .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.bgTerminal)
    }
}

struct WebCanvas: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.allowsBackForwardNavigationGestures = true
        web.isOpaque = false
        web.backgroundColor = .clear
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        // Reloads happen by replacing the view (`.id(reloadToken)`), so nothing to do.
    }
}
