// DeepSeek Bot for iOS — Apache-2.0
// 供应商·自定义模型. This is the screen that makes "every Bot on its own model" real:
// `provider-add` with `custom: true` registers an endpoint DSH ships nothing about, and
// from then on its models appear in every Bot's model picker as one more group.
//
// Field names and the protocol list come from ds-bot/src/host/providers.js:
//   PROTOCOLS = ['openai-completions', 'openai-responses', 'anthropic-messages']
//   customProfile(body) reads { name?, api, baseURL, models: [{id, name?}] }
// A key is only ever written; the host never reads one back.

import SwiftUI

struct ProvidersView: View {
    @EnvironmentObject private var model: TeamModel

    @State private var showAdd = false
    @State private var routeId = ""
    @State private var displayName = ""
    @State private var baseURL = ""
    @State private var protocolName = "openai-completions"
    @State private var apiKey = ""
    @State private var modelIds = ""
    @State private var discovered: [DiscoveredModel] = []
    @State private var isDiscovering = false
    @State private var keyFieldFor: String?

    private var theme: DSBTheme { model.theme }
    private var view: ProviderDirectory { model.providers }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(theme.promptBorder).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    explainer
                    if view.available == false {
                        unavailable
                    } else {
                        configured
                        addForm
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 28)
            }
        }
        .background(theme.bgBase)
        .task { await model.loadProviders() }
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
                Text("供应商")
                    .font(.body.monospaced().weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
                Text("接自定义模型 · 每个 Bot 各选一个")
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.gray)
            }
            Spacer()
            Button {
                Task { await model.loadProviders() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .padding(8)
                    .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.bgTerminal)
    }

    private var explainer: some View {
        Text("""
        加一个自定义供应商 = 给宿主多接一路算力。支持 OpenAI 兼容、OpenAI Responses、\
        Anthropic 三种协议，任何自建网关、中转、本地推理都算在内。加完之后，它的模型会\
        出现在「新建/编辑 Bot」的模型下拉里，每个 Bot 可以各选一个。
        """)
        .font(.caption.monospaced())
        .foregroundStyle(theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
        .background(theme.bgHighlight)
    }

    private var unavailable: some View {
        Text("这个宿主没有开放供应商设置（`providers.available = false`）。它的模型只能在宿主的 DSH 设置里改，手机端仍然可以给每个 Bot 选模型。")
            .font(.caption.monospaced())
            .foregroundStyle(theme.accentPlan)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var configured: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已接的供应商 · \(view.providerList.count)")
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(theme.textSecondary)

            ForEach(view.providerList) { provider in
                providerRow(provider)
            }
        }
    }

    private func providerRow(_ provider: Provider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(provider.title)
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textPrimary)
                if provider.custom == true {
                    Text("自定义")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.accentSuccess)
                }
                Spacer()
                Text("\(provider.modelCount) 个模型")
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.gray)
            }

            if let id = provider.id {
                Text(id)
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.grayDim)
            }

            if let error = provider.error, !error.isEmpty {
                Text(error)
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.accentError)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 14) {
                if provider.key != nil {
                    Text(provider.hasKey ? "已配置密钥" : "没有密钥")
                        .font(.caption2.monospaced())
                        .foregroundStyle(provider.hasKey ? theme.accentSuccess : theme.accentPlan)
                    if provider.canWriteKey {
                        Button(keyFieldFor == provider.id ? "收起" : (provider.hasKey ? "换密钥" : "填密钥")) {
                            keyFieldFor = keyFieldFor == provider.id ? nil : provider.id
                        }
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.accentAssistant)
                        .buttonStyle(.plain)
                    }
                } else {
                    Text("不需要密钥")
                        .font(.caption2.monospaced())
                        .foregroundStyle(theme.grayDim)
                }
                Spacer()
                if provider.removable == true {
                    Button("删除") {
                        Task { _ = await model.removeProvider(provider) }
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.accentError)
                    .buttonStyle(.plain)
                }
            }

            if keyFieldFor == provider.id, let id = provider.id {
                HStack(spacing: 8) {
                    SecureKeyField(placeholder: "粘贴 API Key", theme: theme) { value in
                        guard !value.isEmpty else { return }
                        Task {
                            if await model.setProviderKey(provider, value: value) {
                                keyFieldFor = nil
                            }
                        }
                    }
                    Button("清除") {
                        Task {
                            if await model.setProviderKey(provider, value: nil) {
                                keyFieldFor = nil
                            }
                        }
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.accentError)
                    .buttonStyle(.plain)
                }
                .id(id)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgTerminal)
        .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
    }

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showAdd.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(showAdd ? "−" : "+")
                        .font(.body.monospaced())
                    Text("接一个自定义供应商")
                        .font(.caption.monospaced().weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(theme.accentAssistant)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showAdd {
                VStack(alignment: .leading, spacing: 12) {
                    label("供应商 id · 小写字母、数字、短横线，字母开头")
                    field {
                        TextField("", text: $routeId, prompt: Text("my-router"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    label("显示名（可选）")
                    field {
                        TextField("", text: $displayName, prompt: Text("我的中转"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    label("接口地址 · 到 /v1 为止")
                    field {
                        TextField("", text: $baseURL, prompt: Text("https://api.example.com/v1"))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }

                    label("协议")
                    Picker("协议", selection: $protocolName) {
                        ForEach(view.protocolList, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(theme.accentAssistant)

                    label("API Key（可选，也可以之后在列表里填）")
                    SecureKeyField(placeholder: "sk-…", theme: theme) { value in
                        apiKey = value
                    }

                    label("模型 id · 一行一个")
                    TextEditor(text: $modelIds)
                        .font(.caption.monospaced())
                        .foregroundStyle(theme.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 76)
                        .padding(8)
                        .background(theme.bgTerminal)
                        .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))

                    HStack(spacing: 14) {
                        Button {
                            Task { await runDiscover() }
                        } label: {
                            HStack(spacing: 6) {
                                if isDiscovering { ProgressView().scaleEffect(0.7).tint(theme.accentAssistant) }
                                Text(isDiscovering ? "正在问接口…" : "发现模型")
                                    .font(.caption.monospaced())
                            }
                            .foregroundStyle(theme.accentAssistant)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDiscovering || baseURL.isEmpty)
                        Spacer()
                    }

                    if !discovered.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("接口说它有 \(discovered.count) 个模型")
                                .font(.caption2.monospaced())
                                .foregroundStyle(theme.gray)
                            ForEach(discovered) { entry in
                                Button {
                                    appendModel(entry.id ?? "")
                                } label: {
                                    HStack(spacing: 6) {
                                        Text("+").font(.caption2.monospaced())
                                        Text(entry.title).font(.caption.monospaced())
                                        Spacer()
                                    }
                                    .foregroundStyle(theme.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                        .background(theme.bgHighlight)
                    }

                    Button {
                        Task { await add() }
                    } label: {
                        HStack(spacing: 8) {
                            if model.isBusy { ProgressView().scaleEffect(0.8).tint(theme.bgTerminal) }
                            Text("加入这个供应商")
                                .font(.body.monospaced().weight(.semibold))
                            Spacer()
                        }
                        .foregroundStyle(theme.bgTerminal)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(canAdd ? theme.accentAssistant : theme.grayDim)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canAdd || model.isBusy)
                }
                .padding(12)
                .background(theme.bgHighlight)
            }
        }
    }

    private var canAdd: Bool {
        !routeId.trimmingCharacters(in: .whitespaces).isEmpty
            && !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !parsedModelIds.isEmpty
    }

    private var parsedModelIds: [String] {
        modelIds
            .split(whereSeparator: { $0 == "\n" || $0 == "," || $0 == " " })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func add() async {
        let ok = await model.addCustomProvider(
            id: routeId,
            name: displayName,
            baseURL: baseURL,
            api: protocolName,
            key: apiKey,
            modelIds: parsedModelIds
        )
        if ok {
            routeId = ""
            displayName = ""
            baseURL = ""
            apiKey = ""
            modelIds = ""
            discovered = []
            showAdd = false
        }
    }

    private func runDiscover() async {
        isDiscovering = true
        discovered = await model.discoverModels(baseURL: baseURL, api: protocolName, key: apiKey)
        isDiscovering = false
    }

    private func appendModel(_ id: String) {
        guard !id.isEmpty else { return }
        var current = parsedModelIds
        if !current.contains(id) { current.append(id) }
        modelIds = current.joined(separator: "\n")
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption2.monospaced())
            .foregroundStyle(theme.gray)
    }

    private func field<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.body.monospaced())
            .foregroundStyle(theme.textPrimary)
            .textFieldStyle(.plain)
            .tint(theme.running)
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .background(theme.bgTerminal)
            .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
    }
}

/// A key is typed once and handed straight to the host; the app never shows it again.
struct SecureKeyField: View {
    let placeholder: String
    let theme: DSBTheme
    let onCommit: (String) -> Void

    @State private var value = ""

    var body: some View {
        HStack(spacing: 8) {
            SecureField("", text: $value, prompt: Text(placeholder))
                .font(.caption.monospaced())
                .foregroundStyle(theme.textPrimary)
                .textFieldStyle(.plain)
                .tint(theme.running)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("保存") {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onCommit(trimmed)
                value = ""
            }
            .font(.caption2.monospaced())
            .foregroundStyle(theme.accentAssistant)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(theme.bgTerminal)
        .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
    }
}

