import SwiftUI

// Settings is split into the standard macOS preference tabs. It used to be one long
// scrolling column of every section stacked together, which made the window very tall and
// gave no sense of where anything lived.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            ProvidersSettingsTab()
                .tabItem { Label("Providers", systemImage: "key.horizontal") }
            SpeechSettingsTab()
                .tabItem { Label("Speech", systemImage: "waveform") }
            CleanupSettingsTab()
                .tabItem { Label("Cleanup", systemImage: "sparkles") }
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - Tab scaffold

/// Every tab is a padded, scrollable column with the same rhythm.
private struct SettingsTab<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        SettingsTab {
            SectionHeader(icon: "slider.horizontal.3", title: "General")

            PermissionsSettingsSection()

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Text insertion").font(.subheadline.weight(.medium))
                Picker("", selection: $appState.insertionMode) {
                    ForEach(InsertionMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup).labelsHidden()
            }

            Divider()

            Toggle(isOn: $appState.showDockIcon) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show Dock icon")
                    Text("Off keeps LazyFlow menu-bar-only. It stays reachable from the menu bar.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Toggle(isOn: $appState.liveTranscriptPreviewEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live transcript preview")
                    Text("Experimental. Shows on-device partial text in the recording overlay while you speak. Doesn't change the final transcript.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .onChange(of: appState.liveTranscriptPreviewEnabled) { _, on in
                if on { SpeechPreviewService.requestAuthorization { _ in } }
            }

            Toggle(isOn: $appState.pressEnterCommandEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice command: press enter")
                    Text("Say “press enter” at the end of a dictation to submit the text.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            SectionHeader(icon: "keyboard", title: "Shortcuts")
            VStack(alignment: .leading, spacing: 8) {
                shortcutRow("Hold Right ⌥", "Push-to-talk — release to transcribe and paste")
                shortcutRow("Double-tap ⌥", "Hands-free toggle recording")
                shortcutRow("Esc",          "Cancel the current recording")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func shortcutRow(_ key: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(key)
                .font(.system(size: 12, design: .monospaced).weight(.semibold))
                .frame(width: 104, alignment: .leading)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Providers

private struct ProvidersSettingsTab: View {
    @Environment(AppState.self) private var appState

    private static let keyedProviders = LLMProvider.allCases.filter { $0 != .custom }

    var body: some View {
        SettingsTab {
            SectionHeader(icon: "wand.and.stars", title: "AI Providers")
            Text("Keys are stored in the system Keychain and never leave your Mac except to call the provider you pick.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(Self.keyedProviders) { provider in
                    ProviderKeyRow(provider: provider, store: appState.providerStore)
                    Divider().padding(.leading, 34)
                }
                ProviderKeyRow(transcriptionProvider: .elevenLabs, store: appState.providerStore)
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            Divider()

            // Provider and model used to clean up completed transcripts.
            DictationCleanupPicker(store: appState.providerStore, providers: Self.keyedProviders)
        }
    }
}

// MARK: - Speech (transcription)

private struct SpeechSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        @Bindable var store = appState.providerStore
        SettingsTab {
            SectionHeader(icon: "waveform", title: "Transcription")

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dictation language").font(.subheadline.weight(.medium))
                    Text("Choosing one language can improve speed and accuracy.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $appState.dictationLanguage) {
                    ForEach(DictationLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden()
                .frame(width: 160)
            }

            Divider()

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
                                badgeColor: Self.badgeColor(model.badge),
                                modelID: model.id,
                                detail: model.detail,
                                isSelected: store.transcriptionModel == model.id
                            ) { store.transcriptionModel = model.id }
                        }
                    }

                    if !store.hasKey(for: store.transcriptionProvider) {
                        Label(
                            "Cloud transcription needs a \(store.transcriptionProvider.displayName) key — add one in the Providers tab.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(LocalSTTModel.allCases) { model in
                        LocalSTTModelCard(model: model)
                    }
                }
                Text("Runs entirely on your Mac — no key and no network. Models are downloaded once and cached.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func badgeColor(_ badge: String) -> Color {
        switch badge {
        case "Fast":         .green
        case "Multilingual": .purple
        default:             .blue
        }
    }
}

// MARK: - Cleanup (post-processing)

private struct CleanupSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        SettingsTab {
            SectionHeader(icon: "cpu", title: "Post-processing")
            Text("How raw speech is cleaned up before it lands at your cursor. Per-app rules live in App Profiles.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("", selection: $appState.llmBackend) {
                Text("Cloud").tag(LLMBackend.cloud)
                Text("On-device (MLX)").tag(LLMBackend.local)
            }
            .pickerStyle(.segmented).labelsHidden()

            if appState.llmBackend == .cloud {
                cloudProviderSummary
            } else {
                VStack(spacing: 8) {
                    ForEach(LocalLLMModel.allCases) { model in
                        LocalLLMModelCard(model: model)
                    }
                }
                Text("Runs entirely on your Mac — no API key required. Smaller models are faster; larger models apply tone rules more reliably.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cloudProviderSummary: some View {
        let store = appState.providerStore
        return HStack(spacing: 10) {
            Image(systemName: store.dictationProvider.icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.dictationProvider.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(store.dictationModel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("Change in Providers")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
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

    private var hasKey: Bool {
        if let provider { return store.hasKey(for: provider) }
        if let transcriptionProvider { return store.hasKey(for: transcriptionProvider) }
        return false
    }
    private var canSave: Bool { !draft.trimmingCharacters(in: .whitespaces).isEmpty }

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
                    // Focus has to be requested after the field exists — setting it in the
                    // same update that flips `isEditing` targets a field that isn't there yet.
                    .onAppear { fieldFocused = true }

                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!canSave)

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

                // Removing a key used to be impossible — the only way out was overwriting it.
                if hasKey {
                    Button {
                        clearKey()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove the \(displayName) key from your Keychain")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .animation(.easeInOut(duration: 0.15), value: isEditing)
    }

    private func clearKey() {
        if let provider { store.clearApiKey(for: provider) }
        else if let transcriptionProvider { store.clearApiKey(for: transcriptionProvider) }
    }

    private func save() {
        guard canSave else { return }
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if let provider { store.setApiKey(trimmed, for: provider) }
        else if let transcriptionProvider { store.setApiKey(trimmed, for: transcriptionProvider) }
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

// MARK: - Dictation cleanup picker (provider + model)

private struct DictationCleanupPicker: View {
    @Bindable var store: LLMProviderStore
    let providers: [LLMProvider]

    @State private var customModel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Dictation Cleanup", systemImage: "waveform.badge.mic")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Picker("", selection: $store.dictationProvider) {
                    ForEach(providers) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
                .onChange(of: store.dictationProvider) { _, provider in
                    store.dictationModel = provider.defaultModel
                    customModel = ""
                }

                Picker("", selection: $store.dictationModel) {
                    ForEach(store.dictationProvider.presetModels) { model in
                        HStack {
                            Text(model.name)
                            if let badge = model.badge {
                                Text("· \(badge)").foregroundStyle(.secondary).font(.caption)
                            }
                        }.tag(model.id)
                    }
                    // Without a row of its own, a custom model ID leaves the picker blank.
                    if !isPreset(store.dictationModel) {
                        HStack {
                            Text(store.dictationModel)
                            Text("· Custom").foregroundStyle(.secondary).font(.caption)
                        }.tag(store.dictationModel)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .onChange(of: store.dictationModel) { _, model in
                    if isPreset(model) { customModel = "" }
                }
            }

            // Preset lists go stale faster than releases do; this is the escape hatch.
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

            if !store.hasKey(for: store.dictationProvider) {
                Label(
                    "No \(store.dictationProvider.displayName) key yet — cleanup will fall back to your Groq key, or be skipped.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func isPreset(_ model: String) -> Bool {
        store.dictationProvider.presetModels.contains { $0.id == model }
    }

    private func applyCustomModel() {
        let normalized = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        store.dictationModel = normalized
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
        }
        .buttonStyle(.plain)
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
    private var errorForMe: String? {
        guard case .error(let msg) = appState.localSTTOpState,
              appState.localSTTModel == model else { return nil }
        return msg
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
                // The STT card silently swallowed load failures — only the LLM card showed them.
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
            ProgressView().controlSize(.small)
        } else if LocalSTTService.isDownloaded(model) {
            HStack(spacing: 8) {
                Button("Use") { appState.loadLocalSTT(model) }.buttonStyle(.borderedProminent).controlSize(.small)
                Button(role: .destructive) { appState.deleteLocalSTT(model) } label: {
                    Image(systemName: "trash").font(.system(size: 11))
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("Delete the downloaded model")
            }
        } else if errorForMe != nil {
            Button("Retry") { appState.loadLocalSTT(model) }
                .buttonStyle(.bordered).controlSize(.small)
        } else {
            Button("Download") { appState.loadLocalSTT(model) }
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
                }
                .buttonStyle(.bordered).controlSize(.small)
                .help("Delete the downloaded model")
            }
        } else if errorForMe != nil {
            Button("Retry") { appState.loadLocalLLM(model) }
                .buttonStyle(.bordered).controlSize(.small)
        } else {
            Button("Download") { appState.loadLocalLLM(model) }
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
