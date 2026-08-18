import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PermissionsSettingsSection()
                Divider().padding(.horizontal, 20)
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
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(icon: "wand.and.stars", title: "AI Providers")
            Text("Keys stored in the system Keychain. Click the lock to edit a key.")
                .font(.caption).foregroundStyle(.secondary)

            // Per-provider key rows
            let providers = LLMProvider.allCases.filter { $0 != .custom }
            VStack(spacing: 0) {
                ForEach(providers) { provider in
                    ProviderKeyRow(provider: provider, store: appState.providerStore)
                    Divider().padding(.leading, 34)
                }
                ProviderKeyRow(transcriptionProvider: .elevenLabs, store: appState.providerStore)
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            // Agent: full provider + model picker
            AgentModelPicker(store: appState.providerStore)
        }
        .padding(20)
    }

    // MARK: - Transcription

    @ViewBuilder
    private func transcriptionSection() -> some View {
        @Bindable var appState = appState
        @Bindable var store = appState.providerStore
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(icon: "waveform", title: "Transcription")

            Picker("", selection: $appState.sttBackend) {
                Text("Cloud").tag(STTBackend.cloud)
                Text("On-device").tag(STTBackend.local)
            }
            .pickerStyle(.segmented).labelsHidden()

            if appState.sttBackend == .cloud {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Provider", selection: $store.transcriptionProvider) {
                        ForEach(TranscriptionProvider.allCases) { provider in
                            Label(provider.displayName, systemImage: provider.icon).tag(provider)
                        }
                    }
                    .onChange(of: store.transcriptionProvider) { _, provider in
                        store.transcriptionModel = provider.defaultModel
                    }

                    HStack(spacing: 10) {
                        ForEach(store.transcriptionProvider.models) { model in
                            CloudModelCard(
                                name: model.name,
                                badge: model.badge,
                                badgeColor: transcriptionBadgeColor(model.badge),
                                modelID: model.id,
                                detail: model.detail,
                                isSelected: store.transcriptionModel == model.id
                            ) { store.transcriptionModel = model.id }
                        }
                    }

                    if appState.providerStore.apiKey(for: store.transcriptionProvider).isEmpty {
                        Label(
                            "Add a \(store.transcriptionProvider.displayName) API key above before recording.",
                            systemImage: "key"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Text("Cloud").tag(LLMBackend.cloud)
                Text("On-device (MLX)").tag(LLMBackend.local)
            }
            .pickerStyle(.segmented).labelsHidden()

            if appState.llmBackend == .cloud {
                DictationModelPicker(store: appState.providerStore)
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

    private func transcriptionBadgeColor(_ badge: String) -> Color {
        switch badge {
        case "Fast":         .green
        case "Multilingual": .purple
        default:             .blue
        }
    }
}

// MARK: - Provider key row (locked by default, unlock to edit)

private struct ProviderKeyRow: View {
    let provider: LLMProvider?
    let transcriptionProvider: TranscriptionProvider?
    @Bindable var store: LLMProviderStore

    @State private var isEditing = false
    @State private var draft     = ""
    @FocusState private var fieldFocused: Bool

    init(provider: LLMProvider, store: LLMProviderStore) {
        self.provider = provider
        self.transcriptionProvider = nil
        self.store = store
    }

    init(transcriptionProvider: TranscriptionProvider, store: LLMProviderStore) {
        self.provider = nil
        self.transcriptionProvider = transcriptionProvider
        self.store = store
    }

    private var storedKey: String {
        if let provider { return store.apiKey(for: provider) }
        if let transcriptionProvider { return store.apiKey(for: transcriptionProvider) }
        return ""
    }
    private var hasKey:    Bool   { !storedKey.isEmpty }

    private var displayName: String {
        provider?.displayName ?? transcriptionProvider?.displayName ?? "Provider"
    }

    private var icon: String {
        provider?.icon ?? transcriptionProvider?.icon ?? "key"
    }

    var body: some View {
        HStack(spacing: 10) {
            // Provider identity
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(hasKey ? Color.accentColor : Color.secondary)
                .frame(width: 20)

            Text(displayName)
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
        if !trimmed.isEmpty {
            if let provider { store.setApiKey(trimmed, for: provider) }
            else if let transcriptionProvider { store.setApiKey(trimmed, for: transcriptionProvider) }
        }
        draft = ""
        isEditing = false
    }

    private var keyPlaceholder: String {
        if transcriptionProvider == .elevenLabs { return "sk_…" }
        guard let provider else { return "API key" }
        return switch provider {
        case .groq:      "gsk_…"
        case .openai:    "sk-…"
        case .google:    "AIza…"
        case .anthropic: "sk-ant-…"
        default:         "API key"
        }
    }
}

// MARK: - Dictation model picker (full provider + model)

private struct DictationModelPicker: View {
    @Bindable var store: LLMProviderStore
    @State private var customModel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cleanup Model", systemImage: "text.badge.checkmark")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Picker("Provider", selection: $store.dictationProvider) {
                    ForEach(LLMProvider.allCases.filter { $0 != .custom && $0 != .anthropic }) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .onChange(of: store.dictationProvider) { _, provider in
                    store.dictationModel = provider.defaultModel(for: .dictation)
                    customModel = ""
                }

                Picker("Model", selection: $store.dictationModel) {
                    ForEach(store.dictationProvider.presetModels) { model in
                        HStack {
                            Text(model.name)
                            if let badge = model.badge {
                                Text("· \(badge)").foregroundStyle(.secondary).font(.caption)
                            }
                        }
                        .tag(model.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .onChange(of: store.dictationModel) { _, model in
                    if store.dictationProvider.presetModels.contains(where: { $0.id == model }) {
                        customModel = ""
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Custom model ID", text: $customModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { applyCustomModel() }
                Button("Use") { applyCustomModel() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text("Groq remains available. OpenAI includes GPT-5.6 Luna and smaller GPT-5.4 models for cost-focused cleanup.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func applyCustomModel() {
        let normalized = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        store.dictationModel = normalized
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
