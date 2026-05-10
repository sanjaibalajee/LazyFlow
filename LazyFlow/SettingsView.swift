import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var apiKeyVisible = false
    @State private var customLLMText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                providerSection()
                Divider().padding(.horizontal, 20)
                transcriptionSection()
                Divider().padding(.horizontal, 20)
                postProcessingSection()
            }
        }
        .frame(width: 520)
    }

    // MARK: - Provider section

    @ViewBuilder
    private func providerSection() -> some View {
        @Bindable var store = appState.providerStore
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(icon: "wand.and.stars", title: "AI Providers")
            Text("Keys stored in the system Keychain. Click the lock to edit a key.")
                .font(.caption).foregroundStyle(.secondary)

            // Per-provider key rows
            let providers = LLMProvider.allCases.filter { $0 != .custom }
            VStack(spacing: 0) {
                ForEach(providers) { provider in
                    ProviderKeyRow(provider: provider, store: appState.providerStore)
                    if provider != providers.last { Divider().padding(.leading, 34) }
                }
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            // Dictation: Groq-only, model picker only
            VStack(alignment: .leading, spacing: 6) {
                Label("Dictation Model", systemImage: "waveform.badge.mic")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Text("Groq")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(width: 36, alignment: .leading)

                    Picker("", selection: $store.dictationModel) {
                        ForEach(LLMProvider.groq.presetModels) { m in
                            HStack {
                                Text(m.name)
                                if let b = m.badge {
                                    Text("· \(b)").foregroundStyle(.secondary).font(.caption)
                                }
                            }.tag(m.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200)
                }
            }

            // Agent: full provider + model picker
            AgentModelPicker(store: appState.providerStore)
        }
        .padding(20)
    }

    // MARK: - Transcription

    @ViewBuilder
    private func transcriptionSection() -> some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "waveform", title: "Transcription")

            Picker("", selection: $appState.sttBackend) {
                Text("Cloud (Groq)").tag(STTBackend.cloud)
                Text("On-device").tag(STTBackend.local)
            }
            .pickerStyle(.segmented).labelsHidden()

            if appState.sttBackend == .cloud {
                HStack(spacing: 10) {
                    ForEach(Self.cloudSTTModels) { m in
                        CloudModelCard(
                            name: m.name, badge: m.badge, badgeColor: m.badgeColor,
                            modelID: m.id, detail: m.detail,
                            isSelected: appState.sttModel == m.id
                        ) { appState.sttModel = m.id }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(LocalSTTModel.allCases) { model in
                        LocalSTTModelCard(model: model)
                    }
                }
            }
        }
        .padding(20)
    }

    // MARK: - Post-processing

    @ViewBuilder
    private func postProcessingSection() -> some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "cpu", title: "Post-processing")

            Picker("", selection: $appState.llmBackend) {
                Text("Cloud (Groq)").tag(LLMBackend.cloud)
                Text("On-device (MLX)").tag(LLMBackend.local)
            }
            .pickerStyle(.segmented).labelsHidden()

            if appState.llmBackend == .cloud {
                cloudLLMSection()
            } else {
                VStack(spacing: 8) {
                    ForEach(LocalLLMModel.allCases) { model in
                        LocalLLMModelCard(model: model)
                    }
                }
                Text("Runs entirely on your Mac — no API key required. Smaller models are faster; larger models apply tone rules more reliably.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private func cloudLLMSection() -> some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                ForEach(Self.cloudLLMPresets) { preset in
                    let isSelected = appState.llmModel == preset.id && customLLMText.isEmpty
                    Button {
                        appState.llmModel = preset.id; customLLMText = ""
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                                Text(preset.description).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(preset.id).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
                    if preset.id != Self.cloudLLMPresets.last?.id { Divider().padding(.leading, 40) }
                }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text("Custom model ID").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    TextField("e.g. llama-3.1-70b-versatile", text: $customLLMText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: customLLMText) { _, val in
                            let t = val.trimmingCharacters(in: .whitespaces)
                            guard !t.isEmpty else { return }
                            appState.llmModel = t
                        }
                    if !customLLMText.isEmpty {
                        Button { customLLMText = ""; appState.llmModel = Self.cloudLLMPresets[0].id } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
                Text("Any model on your Groq account. See [console.groq.com/docs/models](https://console.groq.com/docs/models)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Static model data

    struct CloudSTTModel: Identifiable {
        let id: String; let name: String; let badge: String; let badgeColor: Color; let detail: String
    }
    static let cloudSTTModels: [CloudSTTModel] = [
        .init(id: "whisper-large-v3",       name: "Large v3",    badge: "Accurate", badgeColor: .blue,
              detail: "Highest accuracy across all languages. Best for technical content. ~2–4s slower."),
        .init(id: "whisper-large-v3-turbo", name: "Large Turbo", badge: "Fast",     badgeColor: .green,
              detail: "6× faster with very good accuracy. Ideal for everyday use."),
    ]

    struct CloudLLMPreset: Identifiable {
        let id: String; let name: String; let description: String
    }
    static let cloudLLMPresets: [CloudLLMPreset] = [
        .init(id: "llama-3.3-70b-versatile", name: "Llama 3.3 70B",        description: "Best quality · recommended default"),
        .init(id: "llama-3.1-8b-instant",    name: "Llama 3.1 8B Instant", description: "Fastest · lowest latency"),
        .init(id: "gemma2-9b-it",            name: "Gemma 2 9B",           description: "Compact, fast, accurate"),
        .init(id: "mixtral-8x7b-32768",      name: "Mixtral 8×7B",         description: "Strong on longer content"),
        .init(id: "openai/gpt-oss-20b",      name: "GPT OSS 20B",          description: "Previous default · OpenAI via Groq"),
    ]
}

// MARK: - Provider key row (locked by default, unlock to edit)

private struct ProviderKeyRow: View {
    let provider:    LLMProvider
    @Bindable var store: LLMProviderStore

    @State private var isEditing = false
    @State private var draft     = ""
    @FocusState private var fieldFocused: Bool

    private var storedKey: String { store.apiKey(for: provider) }
    private var hasKey:    Bool   { !storedKey.isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            // Provider identity
            Image(systemName: provider.icon)
                .font(.system(size: 11))
                .foregroundStyle(hasKey ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            Text(provider.displayName)
                .font(.system(size: 13))
                .frame(width: 124, alignment: .leading)

            if isEditing {
                // Edit mode — text field + Save / Cancel
                SecureField(keyPlaceholder, text: $draft)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit { save() }

                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty &&
                              draft != storedKey)

                Button("Cancel") {
                    draft = ""
                    isEditing = false
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            } else {
                // Locked — show masked key or placeholder
                Group {
                    if hasKey {
                        Text(String(repeating: "•", count: 20))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No key")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Lock/unlock button
                Button {
                    draft = ""  // never pre-fill with the actual key
                    isEditing = true
                    fieldFocused = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: hasKey ? "lock.fill" : "plus.circle")
                            .font(.system(size: 11))
                        Text(hasKey ? "Change" : "Add Key")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .animation(.easeInOut(duration: 0.15), value: isEditing)
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { store.setApiKey(trimmed, for: provider) }
        draft = ""
        isEditing = false
    }

    private var keyPlaceholder: String {
        switch provider {
        case .groq:      "gsk_…"
        case .openai:    "sk-…"
        case .google:    "AIza…"
        case .anthropic: "sk-ant-…"
        default:         "API key"
        }
    }
}

// MARK: - Agent model picker (full provider + model)

private struct AgentModelPicker: View {
    @Bindable var store: LLMProviderStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Computer Use Agent", systemImage: "sparkles")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Picker("", selection: $store.agentProvider) {
                    ForEach(LLMProvider.allCases.filter { $0 != .custom }) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .onChange(of: store.agentProvider) { _, p in
                    store.agentModel = p.defaultModel(for: .agent)
                }

                Picker("", selection: $store.agentModel) {
                    ForEach(store.agentProvider.presetModels) { m in
                        HStack {
                            Text(m.name)
                            if let b = m.badge {
                                Text("· \(b)").foregroundStyle(.secondary).font(.caption)
                            }
                        }.tag(m.id)
                    }
                }
                .labelsHidden()

                // Capability badges for selected model
                if let spec = store.agentProvider.presetModels.first(where: { $0.id == store.agentModel }) {
                    if spec.vision { badgePill("Vision", color: .blue)  }
                    if spec.tools  { badgePill("Tools",  color: .purple) }
                }
            }
        }
    }
}

// MARK: - Cloud model card

private struct CloudModelCard: View {
    let name: String; let badge: String; let badgeColor: Color
    let modelID: String; let detail: String
    let isSelected: Bool; let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? badgeColor : .secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(isSelected ? badgeColor.opacity(0.12) : Color.secondary.opacity(0.1), in: Capsule())
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 13)).foregroundStyle(Color.accentColor)
                    }
                }
                Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                Text(modelID).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

// MARK: - Local STT card

private struct LocalSTTModelCard: View {
    @Environment(AppState.self) private var appState
    let model: LocalSTTModel

    private var isActive: Bool {
        appState.localSTTModel == model && appState.localSTTOpState == .idle && LocalSTTService.isDownloaded(model)
    }
    private var isBusyForMe: Bool {
        guard case .busy = appState.localSTTOpState else { return false }
        return appState.localSTTModel == model
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.displayName).font(.system(size: 13, weight: .semibold))
                    badgePill(model.sizeLabel, color: .secondary)
                    if model == .parakeetV3 { badgePill("Recommended", color: .green) }
                }
                Text(model.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                if isBusyForMe, case .busy(let p, let s) = appState.localSTTOpState {
                    progressRow(p, s)
                }
            }
            Spacer()
            actionButton()
        }
        .padding(12)
        .background(isActive ? Color.accentColor.opacity(0.06) : Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isActive ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1))
    }

    @ViewBuilder private func actionButton() -> some View {
        if isActive {
            Label("Active", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
        } else if isBusyForMe {
            ProgressView().controlSize(.small)
        } else if LocalSTTService.isDownloaded(model) {
            HStack(spacing: 8) {
                Button("Use") { appState.loadLocalSTT(model) }.buttonStyle(.borderedProminent).controlSize(.small)
                Button(role: .destructive) { appState.deleteLocalSTT(model) } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }.buttonStyle(.bordered).controlSize(.small)
            }
        } else {
            Button("Download") { appState.localSTTModel = model; appState.loadLocalSTT(model) }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(appState.localSTTOpState.isBusy)
        }
    }
}

// MARK: - Local LLM card

private struct LocalLLMModelCard: View {
    @Environment(AppState.self) private var appState
    let model: LocalLLMModel

    private var isActive: Bool {
        appState.localLLMModel == model && appState.localLLMOpState == .idle && LocalLLMService.isDownloaded(model)
    }
    private var isBusyForMe: Bool {
        guard case .busy = appState.localLLMOpState else { return false }
        return appState.localLLMModel == model
    }
    private var errorForMe: String? {
        guard case .error(let msg) = appState.localLLMOpState,
              appState.localLLMModel == model else { return nil }
        return msg
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.displayName).font(.system(size: 13, weight: .semibold))
                    badgePill(model.sizeLabel, color: .secondary)
                    badgePill(model.badge, color: model.badgeColor)
                }
                Text(model.detail).font(.system(size: 11)).foregroundStyle(.secondary)
                if isBusyForMe, case .busy(let p, let s) = appState.localLLMOpState {
                    progressRow(p, s)
                }
                if let err = errorForMe {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .padding(.top, 2)
                }
            }
            Spacer()
            actionButton()
        }
        .padding(12)
        .background(
            errorForMe != nil
                ? Color.red.opacity(0.04)
                : isActive ? Color.accentColor.opacity(0.06) : Color.secondary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(
                errorForMe != nil
                    ? Color.red.opacity(0.25)
                    : isActive ? Color.accentColor.opacity(0.3) : Color.clear,
                lineWidth: 1
            )
        )
    }

    @ViewBuilder private func actionButton() -> some View {
        if isActive {
            Label("Active", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
        } else if isBusyForMe {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Button("Cancel") { appState.cancelLocalLLM() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
        } else if LocalLLMService.isDownloaded(model) {
            HStack(spacing: 8) {
                Button("Use") { appState.loadLocalLLM(model) }.buttonStyle(.borderedProminent).controlSize(.small)
                Button(role: .destructive) { appState.deleteLocalLLM(model) } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }.buttonStyle(.bordered).controlSize(.small)
            }
        } else if errorForMe != nil {
            Button("Retry") { appState.localLLMModel = model; appState.loadLocalLLM(model) }
                .buttonStyle(.bordered).controlSize(.small)
        } else {
            Button("Download") { appState.localLLMModel = model; appState.loadLocalLLM(model) }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(appState.localLLMOpState.isBusy)
        }
    }
}

// MARK: - Shared helpers

@ViewBuilder
private func badgePill(_ text: String, color: Color) -> some View {
    Text(text)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(color.opacity(0.1), in: Capsule())
}

@ViewBuilder
private func progressRow(_ progress: Double, _ status: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        ProgressView(value: progress).tint(.accentColor)
        Text(status).font(.system(size: 10)).foregroundStyle(.secondary)
    }
    .padding(.top, 4)
}

// MARK: - Section header

private struct SectionHeader: View {
    let icon: String; let title: String
    var body: some View { Label(title, systemImage: icon).font(.headline) }
}
