// DeepSeek Bot for iOS — Apache-2.0
// Shapes for the three endpoints that make the phone a manager rather than a viewer:
//   providers  → ds-bot/src/host/providers.js  providersView()
//   efforts    → ds-bot/src/host/models.js     reasoningOf()
//   folders    → ds-bot/src/host/folders.js    folderEndpoint('folders')

import Foundation

// MARK: - Providers

struct ProviderDirectory: Decodable {
    var available: Bool?
    var providers: [Provider]?
    var addable: [AddableProvider]?
    var protocols: [String]?

    init() {}

    var providerList: [Provider] { providers ?? [] }
    var addableList: [AddableProvider] { addable ?? [] }
    /// `['openai-completions', 'openai-responses', 'anthropic-messages']` — the host
    /// decides; this list is only ever displayed or sent back verbatim.
    var protocolList: [String] {
        let given = protocols ?? []
        return given.isEmpty
            ? ["openai-completions", "openai-responses", "anthropic-messages"]
            : given
    }
}

struct Provider: Decodable, Identifiable {
    var id: String?
    var name: String?
    var models: [ProviderModel]?
    /// Present only when this provider takes a key here; `configured` is all the host
    /// will ever say — a key is written, never read back.
    var key: ProviderKey?
    var removable: Bool?
    var custom: Bool?
    var error: String?

    init() {}

    var uid: String { id ?? name ?? "provider" }
    var title: String { name ?? id ?? "供应商" }
    var modelCount: Int { models?.count ?? 0 }
    var hasKey: Bool { key?.configured == true }
    var canWriteKey: Bool { key?.writable ?? false }
}

struct ProviderModel: Decodable, Identifiable {
    var ref: String?
    var name: String?

    init() {}

    var id: String { ref ?? name ?? "model" }
    var title: String { name ?? ref ?? "模型" }
}

struct ProviderKey: Decodable {
    var configured: Bool?
    var writable: Bool?
}

struct AddableProvider: Decodable, Identifiable {
    var id: String?
    var name: String?

    init() {}

    var uid: String { id ?? name ?? "provider" }
    var title: String { name ?? id ?? "供应商" }
}

/// What `provider-models` answers for a custom endpoint.
struct DiscoveredModel: Decodable, Identifiable {
    var id: String?
    var name: String?
    var contextWindow: Int?
    var maxTokens: Int?

    init() {}

    var uid: String { id ?? name ?? "model" }
    var title: String { name ?? id ?? "模型" }
}

// MARK: - Thinking levels

struct EffortCatalog: Decodable {
    var efforts: [Effort]?
    var defaultEffort: String?

    init() {}

    var list: [Effort] { efforts ?? [] }
}

struct Effort: Decodable, Identifiable {
    var id: String?
    var name: String?
    var description: String?

    init() {}

    var uid: String { id ?? name ?? "effort" }
    var title: String { name ?? id ?? "默认" }
}

// MARK: - Working directories

/// `folders` answers the team folder plus every folder a Bot or room already works in.
/// It is not a filesystem browser: browsing lives behind `folder-list`, which only a
/// host with a browse picker answers.
struct FolderCatalog: Decodable {
    var team: String?
    var picker: String?
    var folders: [FolderOption]?

    init() {}

    var list: [FolderOption] { folders ?? [] }
}

struct FolderOption: Decodable, Identifiable {
    var path: String?
    var title: String?

    init() {}

    var uid: String { path ?? title ?? "folder" }
    var name: String {
        if let title, !title.isEmpty { return title }
        guard let path else { return "文件夹" }
        return path.split(separator: "/").last.map(String.init) ?? path
    }
}

// MARK: - Colors

/// `state.colors` — the palette a Bot may be given. `#rrggbb`.
struct PaletteColor: Decodable, Identifiable {
    var hex: String?

    init() {}

    var id: String { hex ?? "color" }
}
