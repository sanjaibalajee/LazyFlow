import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var apiKeyVisible = false
    @State private var customLLMText = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                apiSection()
                Divider().padding(.horizontal, 20)
                transcriptionSection()
                Divider().padding(.horizontal, 20)
                postProcessingSection()
            }
        }
        .frame(width: 500)
        .onAppear {
            if !Self.llmPresets.map(\.id).contains(appState.llmModel) {
                customLLMText = appState.llmModel
            }
        }
    }

    // MARK: - API Key

    @ViewBuilder
    private func apiSection() -> some View {
        @Bindable var appState = appState
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "key.fill", title: "Groq API Key")

            HStack(spacing: 8) {
                Group {
                    if apiKeyVisible {
                        TextField("gsk_…", text: $appState.apiKey)
                    } else {
                        SecureField("gsk_…", text: $appState.apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

                Button { apiKeyVisible.toggle() } label: {
                    Image(systemName: apiKeyVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text("Stored in the system keychain. Get a free key at [groq.com](https://groq.com)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    // MARK: - Transcription

    @ViewBuilder
    private func transcriptionSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "waveform", title: "Transcription Model")

            HStack(spacing: 10) {
                ForEach(Self.sttModels) { model in
                    STTModelCard(model: model, isSelected: appState.sttModel == model.id) {
                        appState.sttModel = model.id
                    }
                }
            }

            if let selected = Self.sttModels.first(where: { $0.id == appState.sttModel }) {
                Text(selected.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
    }

    // MARK: - Post-processing

    @ViewBuilder
    private func postProcessingSection() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(icon: "cpu", title: "Post-processing Model")

            VStack(spacing: 0) {
                ForEach(Self.llmPresets) { preset in
                    let isSelected = appState.llmModel == preset.id && customLLMText.isEmpty
                    Button {
                        appState.llmModel = preset.id
                        customLLMText = ""
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.4))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                Text(preset.description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(preset.id)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)

                    if preset.id != Self.llmPresets.last?.id {
                        Divider().padding(.leading, 40)
                    }
                }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text("Custom model ID")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("e.g. llama-3.1-70b-versatile", text: $customLLMText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: customLLMText) { _, val in
                            let trimmed = val.trimmingCharacters(in: .whitespaces)
                            if trimmed.isEmpty {
                                appState.llmModel = Self.llmPresets.first?.id ?? appState.llmModel
                            } else {
                                appState.llmModel = trimmed
                            }
                        }

                    if !customLLMText.isEmpty {
                        Button {
                            customLLMText = ""
                            appState.llmModel = Self.llmPresets[0].id
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("Any model on your Groq account. See [console.groq.com/docs/models](https://console.groq.com/docs/models)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
    }

    // MARK: - Model data

    struct STTModelInfo: Identifiable {
        let id: String
        let name: String
        let badge: String
        let badgeColor: Color
        let detail: String
    }

    static let sttModels: [STTModelInfo] = [
        STTModelInfo(
            id: "whisper-large-v3",
            name: "Large v3",
            badge: "Accurate",
            badgeColor: .blue,
            detail: "Highest accuracy across all languages and accents. Best for technical content, proper nouns, and mixed-language input. ~2–4s slower than Turbo."
        ),
        STTModelInfo(
            id: "whisper-large-v3-turbo",
            name: "Large v3 Turbo",
            badge: "Fast",
            badgeColor: .green,
            detail: "6× faster with very good accuracy. Ideal for everyday casual use, short messages, and when latency matters more than perfection."
        ),
    ]

    struct LLMPreset: Identifiable {
        let id: String
        let name: String
        let description: String
    }

    static let llmPresets: [LLMPreset] = [
        LLMPreset(id: "llama-3.3-70b-versatile", name: "Llama 3.3 70B",        description: "Best quality · recommended default"),
        LLMPreset(id: "llama-3.1-8b-instant",    name: "Llama 3.1 8B Instant", description: "Fastest · lowest latency"),
        LLMPreset(id: "gemma2-9b-it",            name: "Gemma 2 9B",           description: "Compact, fast, accurate"),
        LLMPreset(id: "mixtral-8x7b-32768",      name: "Mixtral 8×7B",         description: "Strong on longer content"),
        LLMPreset(id: "openai/gpt-oss-20b",      name: "GPT OSS 20B",          description: "Previous default · OpenAI via Groq"),
    ]
}

// MARK: - STT Model Card

private struct STTModelCard: View {
    let model:      SettingsView.STTModelInfo
    let isSelected: Bool
    let onSelect:   () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isSelected ? model.badgeColor : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            isSelected ? model.badgeColor.opacity(0.12) : Color.secondary.opacity(0.1),
                            in: Capsule()
                        )
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Text(model.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(model.id)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Section Header

private struct SectionHeader: View {
    let icon:  String
    let title: String
    var body: some View {
        Label(title, systemImage: icon).font(.headline)
    }
}
