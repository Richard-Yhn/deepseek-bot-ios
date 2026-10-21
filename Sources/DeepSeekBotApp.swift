// DeepSeek Bot for iOS — Apache-2.0

import SwiftUI
import Foundation

@main
struct DeepSeekBotApp: App {
    @StateObject private var model = TeamModel()

    init() {
        // The host authenticates the browser with a signed cookie; URLSession has to
        // keep the one the login URL sets, or every /api/bot call is a 401.
        HTTPCookieStorage.shared.cookieAcceptPolicy = .always
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { await model.restore() }
        }
    }
}
