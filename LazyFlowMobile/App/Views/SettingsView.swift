import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: ProcessingSettings
    var hasSharedContainer: Bool
    var showKeyboardSetup: () -> Void

    @State private var keyDraft = ""
    @State private var keyStatus: KeyStatus = .idle
    @State private var showingRemoveKeyConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                pipelineSection
                transcriptionSection
                rewriteSection
                groqKeySection
                keyboardSection
                privacySection
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Remove Groq API key?",
                isPresented: $showingRemoveKeyConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove key", role: .destructive) { removeKey() }
            } message: {
                Text("Cloud transcription and rewriting will switch back to Apple On-Device.")
            }
        }
    }

    private var pipelineSection: some View {
        Section {
            modelSummaryRow(
                symbol: "waveform",
                title: "Transcription",
                value: transcriptionSummary
            )
            modelSummaryRow(
                symbol: "wand.and.sparkles",
                title: "Tone rewrite",
                value: rewriteSummary
            )
        } header: {
            Text("Current pipeline")
        } footer: {
            Text(settings.needsGroqKey
                 ? "Audio or transcript text is sent to Groq only for the cloud steps selected above."
                 : "Both steps stay on this iPhone. No API key is required.")
        }
    }

    private var transcriptionSection: some View {
        Section("Speech to text") {
            Picker("Provider", selection: $settings.transcriptionProvider) {
                ForEach(TranscriptionProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }

            if settings.transcriptionProvider == .groq {
                Picker("Model", selection: $settings.speechModel) {
                    ForEach(GroqSpeechModel.allCases) { model in
                        VStack(alignment: .leading) {
                            Text(model.title)
                            Text(model.rawValue)
                        }
                        .tag(model)
                    }
                }
                modelDescription(
                    settings.speechModel.title,
                    identifier: settings.speechModel.rawValue,
                    detail: settings.speechModel.subtitle
                )
            } else {
                modelDescription(
                    "SpeechAnalyzer",
                    identifier: "Apple Speech",
                    detail: "Downloads the matching language model and transcribes locally."
                )
            }
        }
    }

    private var rewriteSection: some View {
        Section("Tone and cleanup") {
            Picker("Provider", selection: $settings.rewriteProvider) {
                ForEach(RewriteProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }

            if settings.rewriteProvider == .groq {
                Picker("Model", selection: $settings.rewriteModel) {
                    ForEach(GroqRewriteModel.allCases) { model in
                        Text(model.title).tag(model)
                    }
                }
                modelDescription(
                    settings.rewriteModel.title,
                    identifier: settings.rewriteModel.rawValue,
                    detail: settings.rewriteModel.subtitle
                )
            } else {
                modelDescription(
                    "Foundation Models",
                    identifier: "Apple Intelligence",
                    detail: "Rewrites on device. LazyFlow uses deterministic cleanup when the model is unavailable."
                )
            }
        }
    }

    private var groqKeySection: some View {
        Section {
            if settings.hasGroqKey {
                HStack {
                    Label("API key", systemImage: "key.fill")
                    Spacer()
                    Text("Saved ····\(settings.keyEnding)")
                        .foregroundStyle(.secondary)
                }
                Button("Replace key") {
                    keyDraft = ""
                    keyStatus = .editing
                }
                Button("Remove key", role: .destructive) {
                    showingRemoveKeyConfirmation = true
                }
            }

            if !settings.hasGroqKey || keyStatus == .editing || keyStatus.isError {
                SecureField("gsk_…", text: $keyDraft)
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    saveAndVerifyKey()
                } label: {
                    HStack {
                        Text("Save and verify key")
                        Spacer()
                        if keyStatus == .verifying {
                            ProgressView()
                        }
                    }
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || keyStatus == .verifying)
            }

            if let message = keyStatus.message {
                Label(message, systemImage: keyStatus.isError ? "exclamationmark.circle" : "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(keyStatus.isError ? Color.red : Color.green)
            }
        } header: {
            Text("Groq")
        } footer: {
            Text("Keys are stored in the iPhone Keychain. Get one from console.groq.com/keys. LazyFlow never places it in the keyboard or history.")
        }
    }

    private var keyboardSection: some View {
        Section {
            Button(action: showKeyboardSetup) {
                HStack {
                    Label("Setup instructions", systemImage: "keyboard")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)

            HStack {
                Label("App Group bridge", systemImage: hasSharedContainer ? "checkmark.shield" : "exclamationmark.shield")
                Spacer()
                Text(hasSharedContainer ? "Available" : "Unavailable")
                    .foregroundStyle(hasSharedContainer ? Color.green : Color.orange)
            }
        } header: {
            Text("Keyboard")
        } footer: {
            if !hasSharedContainer {
                Text("This build has no shared container. Do not disable code signing; both targets must be signed with group.com.fanpit.LazyFlow.")
            } else {
                Text("Full Access is required only for the private App Group command bridge.")
            }
        }
    }

    private var privacySection: some View {
        Section("Privacy") {
            Label("History stays on this iPhone", systemImage: "iphone.and.arrow.forward")
            Label("Voice sessions expire after 30 minutes", systemImage: "timer")
            Label("The keyboard never receives microphone audio", systemImage: "mic.slash")
        }
    }

    private var transcriptionSummary: String {
        settings.transcriptionProvider == .apple
            ? "Apple SpeechAnalyzer"
            : settings.speechModel.title
    }

    private var rewriteSummary: String {
        settings.rewriteProvider == .apple
            ? "Apple Foundation Models"
            : settings.rewriteModel.title
    }

    private func modelSummaryRow(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(title)
                .layoutPriority(1)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .frame(maxWidth: 170, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func modelDescription(_ title: String, identifier: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(identifier)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func saveAndVerifyKey() {
        let candidate = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        keyStatus = .verifying
        Task {
            do {
                try await GroqService().validateAPIKey(candidate)
                try settings.saveGroqKey(candidate)
                keyDraft = ""
                keyStatus = .saved
            } catch {
                keyStatus = .error(error.localizedDescription)
            }
        }
    }

    private func removeKey() {
        do {
            try settings.removeGroqKey()
            keyDraft = ""
            keyStatus = .idle
        } catch {
            keyStatus = .error(error.localizedDescription)
        }
    }
}

private enum KeyStatus: Equatable {
    case idle
    case editing
    case verifying
    case saved
    case error(String)

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var message: String? {
        switch self {
        case .saved: "Key verified and saved securely."
        case .error(let message): message
        default: nil
        }
    }
}
