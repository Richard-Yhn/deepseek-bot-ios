// DeepSeek Bot for iOS — Apache-2.0
// Screen routing and connection phases, kept in the vocabulary of grok-build-ios
// (ios/GrokApp/GrokApp/Models/ScrollbackEntry.swift) so the two clients read alike.

import Foundation

enum AppScreen: Equatable {
    case welcome
    case team
    case chat
    case rooms
    case dispatch
    case providers
    case direct
    case settings
    case web
}

enum ConnectionPhase: Equatable {
    case idle
    case checking
    case succeeded
    case failed(String)
}

/// A permission row. In Grok these come from ACP `session/request_permission`; here
/// they come from ds-bot's approvals — same shape, same banner.
struct PermissionOption: Equatable, Identifiable {
    let optionId: String
    let name: String
    let kind: String

    var id: String { optionId }

    static let allow = PermissionOption(optionId: "allow", name: "允许这一次", kind: "allow_once")
    static let reject = PermissionOption(optionId: "reject", name: "拒绝", kind: "reject_once")
}

struct PermissionRequest: Equatable {
    let message: String
    let title: String?
    let options: [PermissionOption]
    var requestId: String?
    var selectedOptionId: String?

    init(
        message: String,
        title: String? = nil,
        options: [PermissionOption] = [.allow, .reject],
        requestId: String? = nil,
        selectedOptionId: String? = nil
    ) {
        self.message = message
        self.title = title
        self.options = options
        self.requestId = requestId
        self.selectedOptionId = selectedOptionId
    }
}

/// Where the connect screen remembers the last host it reached.
enum HostStore {
    private static let key = "DSB_HOST"

    static func load() -> HostAddress? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HostAddress.self, from: data)
    }

    static func save(_ address: HostAddress) {
        guard let data = try? JSONEncoder().encode(address) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Small appearance toggles, in the same UserDefaults style as grok's `AppSettings`.
enum DSBSettings {
    private static let timestampsKey = "DSB_SHOW_TIMESTAMPS"
    private static let brightnessKey = "DSB_THEME_IS_DARK"

    static var showTimestamps: Bool {
        get {
            if UserDefaults.standard.object(forKey: timestampsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: timestampsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: timestampsKey) }
    }

    static var isDark: Bool {
        get {
            if UserDefaults.standard.object(forKey: brightnessKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: brightnessKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: brightnessKey) }
    }
}
