// DeepSeek Bot for iOS — Apache-2.0
// New / edit one Bot. Three things this sheet exists for:
//
//   1. 模型 —— every Bot carries its own model ref, so a team can mix the DeepSeek
//      default with models from a custom provider (`provider-add`). The picker lists
//      the whole catalog grouped by provider, plus a field for a ref the catalog does
//      not have yet.
//   2. 任务 —— `brief` is the one-line assignment, `instructions` the standing order.
//      Giving five Bots five briefs is how one job gets worked in parallel.
//   3. 工作目录 —— the folder this Bot reads and writes, from the folders the team
//      already knows (`folders`).

import SwiftUI

struct ManageBotView: View {
    @EnvironmentObject private var model: TeamModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: BotDraft
    @State private var efforts = EffortCatalog()
    @State private var folders: [FolderOption] = []
    @State private var manualModel: String = ""
    @State private var showManualModel = false
    @State private var confirmDelete = false

    private let existing: Bot?

    init(bot: Bot? = nil) {
        existing = bot
        _draft = State(initialValue: bot.map { BotDraft(bot: $0) } ?? BotDraft())
    }

    private var theme: DSBTheme { model.theme }
    private var flatModels: [ModelEntry] { model.team.modelGroups.flatMap(\.models) }
    private var isEditing: Bool { existing != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleBar
                identity
                modelSection
                taskSection
                folderSection
                if isEditing { dangerSection }
                saveButton
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.bgBase)
        .task {
            folders = await model.loadFolders().list
            await reloadEfforts()
            if let ref = existing?.model, !ref.isEmpty { manualModel = ref }
        }
        .confirmationDialog(
            "删除 \(existing?.displayName ?? "这个 Bot")？",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                guard let existing else { return }
                Task {
                    if await model.deleteBot(existing) { dismiss() }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("它自己的会话会留在宿主里，但团队里不再有它。")
        }
    }

    // MARK: - Chrome

    private var titleBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(isEditing ? "编辑 Bot" : "新建 Bot")
                .font(.body.monospaced().weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Spacer()
            Button("取消") { dismiss() }
                .font(.caption.monospaced())
                .foregroundStyle(theme.textSecondary)
                .buttonStyle(.plain)
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("名称")
            field {
                TextField("", text: $draft.name, prompt: Text("比如 阿鲸"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            label("角色 · 一句话，最多 24 字")
            field {
                TextField("", text: $draft.role, prompt: Text("比如 架构 · 评审"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            label("颜色")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BotInk.names, id: \.self) { name in
                        Circle()
                            .fill(BotInk.color(name))
                            .frame(width: 22, height: 22)
                            .overlay(
                                Circle().stroke(
                                    draft.color == name ? theme.textPrimary : Color.clear,
                                    lineWidth: 2
                                )
                            )
                            .onTapGesture { draft.color = name }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Model

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("模型 · 这个 Bot 用哪份算力")
            if flatModels.isEmpty {
                Text("宿主的模型目录是空的。先去「供应商」加一个模型（可以是自定义接口），再回来选。")
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.accentPlan)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("模型", selection: $draft.model) {
                    Text("跟随宿主默认").tag("")
                    ForEach(flatModels, id: \.ref) { entry in
                        Text("\(entry.providerTitle) · \(entry.shortName)").tag(entry.ref ?? "")
                    }
                }
                .pickerStyle(.menu)
                .tint(theme.accentAssistant)
                .onChange(of: draft.model) { _, _ in
                    draft.effort = ""
                    Task { await reloadEfforts() }
                }
            }

            if showManualModel {
                field {
                    TextField("", text: $manualModel, prompt: Text("my-router/llama-3.1-70b"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                HStack(spacing: 8) {
                    Button("用这个 ref") {
                        draft.model = manualModel.trimmingCharacters(in: .whitespaces)
                        Task { await reloadEfforts() }
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.accentAssistant)
                    .buttonStyle(.plain)
                    Spacer()
                }
            }

            if !efforts.list.isEmpty {
                Picker("思考档位", selection: $draft.effort) {
                    Text("默认").tag("")
                    ForEach(efforts.list, id: \.uid) { effort in
                        Text(effort.title).tag(effort.id ?? "")
                    }
                }
                .pickerStyle(.menu)
                .tint(theme.textPrimary)
            }

            HStack(spacing: 14) {
                Button(showManualModel ? "收起手填" : "手填模型 ref") {
                    showManualModel.toggle()
                }
                Button("去加自定义供应商") {
                    dismiss()
                    model.screen = .providers
                }
                Spacer()
            }
            .font(.caption.monospaced())
            .foregroundStyle(theme.textSecondary)
            .buttonStyle(.plain)

            if let ref = optionalModel, model.team.isCustomModel(ref) {
                Text("自定义供应商的模型 · \(ref)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.accentSuccess)
            }
        }
    }

    private var optionalModel: String? {
        let value = draft.model.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    // MARK: - Task

    private var taskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("任务 · 它在团队里干什么")
            label("一句话任务（会一直挂在它的提示里）")
            field {
                TextField("", text: $draft.brief, prompt: Text("比如 盯着构建，坏了就修"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            label("长期要求")
            TextEditor(text: $draft.instructions)
                .font(.body.monospaced())
                .foregroundStyle(theme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(8)
                .background(theme.bgTerminal)
                .overlay(Rectangle().stroke(theme.promptBorder, lineWidth: 1))
        }
    }

    private var folderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("工作目录")
            Picker("工作目录", selection: $draft.workDir) {
                Text("不指定").tag("")
                ForEach(folders, id: \.id) { folder in
                    Text(folder.name).tag(folder.path ?? "")
                }
            }
            .pickerStyle(.menu)
            .tint(theme.textPrimary)
            if let path = optionalWorkDir {
                Text(path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(theme.gray)
                    .lineLimit(2)
            }
            Text("列表来自团队已经在用的目录。要选别的，去「完整界面」用宿主的文件夹选择器。")
                .font(.caption2.monospaced())
                .foregroundStyle(theme.grayDim)
        }
    }

    private var optionalWorkDir: String? {
        let value = draft.workDir.trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("其他")
            if let existing, !model.team.isMain(existing) {
                Button {
                    Task {
                        if await model.setMain(existing) { dismiss() }
                    }
                } label: {
                    rowLabel("设为团队的主 Bot", symbol: "star", color: theme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            Button {
                confirmDelete = true
            } label: {
                rowLabel("删除这个 Bot", symbol: "trash", color: theme.accentError)
            }
            .buttonStyle(.plain)
        }
    }

    private func rowLabel(_ title: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.caption)
            Text(title).font(.caption.monospaced())
            Spacer()
        }
        .foregroundStyle(color)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var saveButton: some View {
        Button {
            Task {
                let ok: Bool
                if isEditing {
                    ok = await model.updateBot(draft)
                } else {
                    ok = await model.createBot(draft)
                }
                if ok { dismiss() }
            }
        } label: {
            HStack(spacing: 8) {
                if model.isBusy {
                    ProgressView().scaleEffect(0.8).tint(theme.bgTerminal)
                }
                Text(isEditing ? "保存" : "创建这个 Bot")
                    .font(.body.monospaced().weight(.semibold))
                Spacer()
            }
            .foregroundStyle(theme.bgTerminal)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(draft.canSubmit ? theme.accentAssistant : theme.grayDim)
        }
        .buttonStyle(.plain)
        .disabled(!draft.canSubmit || model.isBusy)
    }

    // MARK: - Bits

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced().weight(.semibold))
            .foregroundStyle(theme.textSecondary)
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

    private func reloadEfforts() async {
        guard let ref = optionalModel else {
            efforts = EffortCatalog()
            return
        }
        efforts = await model.loadEfforts(for: ref)
    }
}

/// Wrapper so a sheet can be driven by "which Bot am I editing" without making each
/// Bot identifiable across the whole app. `bot == nil` means "new Bot".
struct ManageTarget: Identifiable {
    let id = UUID()
    let bot: Bot?
}
