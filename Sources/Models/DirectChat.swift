// DeepSeek Bot for iOS — Apache-2.0
// 手机自己也有一份算力.
//
// The desktop team is the main path, but the phone is not only a pager: with an
// OpenAI-compatible endpoint and a key, it can hold its own conversation — on a plane,
// on mobile data, with the host asleep. And because this chat is just text, anything
// worth keeping can be handed to a Bot on the host afterwards (`send`).

import Foundation

struct DirectMessage: Codable, Identifiable, Equatable {
    var id: String
    var role: String
    var text: String

    init(id: String = UUID().uuidString, role: String, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }

    var isUser: Bool { role == "user" }
}

/// Any OpenAI-compatible endpoint. `baseURL` should end at the version segment
/// (`https://api.deepseek.com/v1`); `/chat/completions` is appended.
struct DirectConfig: Codable, Equatable {
    var baseURL: String
    var apiKey: String
    var model: String
    var systemPrompt: String

    init(baseURL: String = "", apiKey: String = "", model: String = "", systemPrompt: String = "") {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.systemPrompt = systemPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        systemPrompt = try container.decodeIfPresent(String.self, forKey: .systemPrompt) ?? ""
    }

    var isUsable: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var endpoint: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard var url = URL(string: withScheme) else { return nil }
        url.appendPathComponent("chat/completions")
        return url
    }
}

enum DirectStore {
    private static let configKey = "DSB_DIRECT_CONFIG"
    private static let messagesKey = "DSB_DIRECT_MESSAGES"

    static func loadConfig() -> DirectConfig {
        guard let data = UserDefaults.standard.data(forKey: configKey),
              let config = try? JSONDecoder().decode(DirectConfig.self, from: data)
        else { return DirectConfig() }
        return config
    }

    static func saveConfig(_ config: DirectConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: configKey)
    }

    static func loadMessages() -> [DirectMessage] {
        guard let data = UserDefaults.standard.data(forKey: messagesKey),
              let list = try? JSONDecoder().decode([DirectMessage].self, from: data)
        else { return [] }
        return list
    }

    static func saveMessages(_ messages: [DirectMessage]) {
        guard let data = try? JSONEncoder().encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: messagesKey)
    }

    static func clearMessages() {
        UserDefaults.standard.removeObject(forKey: messagesKey)
    }
}
