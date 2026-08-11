import SwiftUI
import AppKit

struct OnboardingView: View {
    let appState: AppState
    let permissions: PermissionsService
    var onFinish: () -> Void

    private enum Step: Int, CaseIterable {
        case welcome, apiKey, personalize, permissions, done

        var title: String {
            switch self {
            case .welcome:     "Welcome"
            case .apiKey:      "Speech"
            case .personalize: "Your style"
            case .permissions: "Permissions"
            case .done:        "Ready"
            }
        }

        var icon: String {
            switch self {
            case .welcome:     "sparkles"
            case .apiKey:      "waveform"
            case .personalize: "slider.horizontal.3"
            case .permissions: "checkmark.shield"
            case .done:        "checkmark"
            }
        }
    }

    @State private var step: Step = .welcome
    @State private var pollingStarted = false
    @State private var didBootstrap = false
    @State private var groqKey = ""
    @State private var selectedAppIDs: Set<String> = []
    @State private var activeAppID: String?
    @State private var appPreferences: [String: String] = [:]
    @State private var isGeneratingProfiles = false
    @State private var didGenerateProfiles = false
    @State private var generatedProfileCount = 0
    @State private var generationNote: String?

    private var isReturningUser: Bool { OnboardingWindowController.hasOnboarded }
    private var activeApp: PopularApp? {
        PopularApp.catalog.first { $0.bundleIdentifier == activeAppID }
    }

    var body: some View {
        ZStack {
            onboardingBackground
            HStack(spacing: 0) {
                stepRail
                VStack(spacing: 0) {
                    ScrollView {
                        content
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.horizontal, 42)
                            .padding(.top, 34)
                            .padding(.bottom, 24)
                    }
                    footer
                }
            }
        }
        .frame(width: 820, height: 660)
        .onAppear(perform: bootstrap)
    }

    private var onboardingBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [Color.accentColor.opacity(0.09), .clear, Color.purple.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color.accentColor.opacity(0.08))
                .frame(width: 360, height: 360)
                .blur(radius: 70)
                .offset(x: 330, y: -250)
        }
        .ignoresSafeArea()
    }

    // MARK: - Navigation rail

    private var stepRail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.gradient)
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 0) {
                    Text("LazyFlow")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("SETUP")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 34)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    stepRow(item)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 5) {
                Label("Private by design", systemImage: "lock.fill")
                    .font(.caption.weight(.medium))
                Text("Keys stay in your Keychain. Profiles stay on this Mac.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(24)
        .frame(width: 210)
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) { Divider() }
    }

    private func stepRow(_ item: Step) -> some View {
        let isCurrent = item == step
        let isComplete = item.rawValue < step.rawValue
        return HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill(isCurrent ? Color.accentColor : isComplete ? Color.green.opacity(0.16) : Color.primary.opacity(0.055))
                Image(systemName: isComplete ? "checkmark" : item.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(isCurrent ? .white : isComplete ? Color.green : Color.secondary)
            }
            .frame(width: 26, height: 26)

            Text(item.title)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
                .foregroundStyle(isCurrent ? .primary : .secondary)
            Spacer()
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(isCurrent ? Color.accentColor.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 9))
    }

    // MARK: - Step content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:     welcomeStep
        case .apiKey:      apiKeyStep
        case .personalize: personalizeStep
        case .permissions: permissionsStep
        case .done:        doneStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer(minLength: 8)
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.11))
                    .frame(width: 108, height: 108)
                Circle()
                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                    .frame(width: 126, height: 126)
                Image(systemName: "waveform.and.mic")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(isReturningUser ? "Tune your flow." : "Your voice, already polished.")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .tracking(-1.2)
                Text("Speak naturally in any app. LazyFlow removes the friction—cleaning, styling, and inserting your words where they belong.")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 500)
            }

            HStack(spacing: 10) {
                featurePill("Any app", icon: "macwindow")
                featurePill("Your style", icon: "slider.horizontal.3")
                featurePill("Voice shortcuts", icon: "text.badge.plus")
            }

            OnboardingCard {
                VStack(alignment: .leading, spacing: 12) {
                    shortcutRow("Hold Right ⌥", "Speak while held; release to paste")
                    Divider()
                    shortcutRow("Double-tap ⌥", "Hands-free recording")
                    Divider()
                    shortcutRow("Say “press enter”", "Paste and submit in one motion")
                }
            }
        }
    }

    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            stepHeading(
                "Fast speech, your language",
                "Connect Groq for cloud Whisper transcription, then narrow language detection when you know what you’ll speak."
            )

            OnboardingCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Label("Groq API key", systemImage: "key.horizontal.fill")
                            .font(.headline)
                        Spacer()
                        Label("Keychain", systemImage: "lock.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }

                    SecureField("gsk_…", text: $groqKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, design: .monospaced))
                        .padding(.horizontal, 13)
                        .frame(height: 42)
                        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.08))
                        }

                    HStack {
                        Text("Used for Whisper and profile generation. Never stored in project files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Link("Create free key ↗", destination: URL(string: "https://console.groq.com/keys")!)
                            .font(.caption.weight(.semibold))
                    }
                }
            }

            OnboardingCard {
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.11))
                        Image(systemName: "globe")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Primary dictation language")
                            .font(.subheadline.weight(.semibold))
                        Text("A fixed language is usually faster and more accurate than automatic detection.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { appState.dictationLanguage },
                        set: { appState.dictationLanguage = $0 }
                    )) {
                        ForEach(DictationLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }

            Label("No key? You can continue and select on-device models later.", systemImage: "cpu")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var personalizeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeading(
                "Make LazyFlow sound like you",
                "Pick the apps you use most, describe the result you want, and LazyFlow will create a safe profile for each one."
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 122), spacing: 9)], spacing: 9) {
                ForEach(PopularApp.catalog) { app in
                    appTile(app)
                }
            }

            if let app = activeApp, selectedAppIDs.contains(app.bundleIdentifier) {
                OnboardingCard {
                    VStack(alignment: .leading, spacing: 13) {
                        HStack(spacing: 10) {
                            AppIcon(bundleIdentifier: app.bundleIdentifier, cornerRadius: 7)
                                .frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("How should you sound in \(app.displayName)?")
                                    .font(.headline)
                                Text("Write naturally—the AI turns this into structured controls.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        TextEditor(text: preferenceBinding(for: app))
                            .font(.system(size: 13, design: .rounded))
                            .scrollContentBackground(.hidden)
                            .padding(9)
                            .frame(minHeight: 74, maxHeight: 90)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.075))
                            }

                        HStack(spacing: 7) {
                            presetChip("Short + lowercase", value: "short, lowercase, conversational, and no trailing period", app: app)
                            presetChip("Professional", value: "warm, concise, professional, with complete sentences", app: app)
                            presetChip("Code precise", value: "preserve code, identifiers, paths, flags, symbols, and exact casing", app: app)
                        }
                    }
                }
            }

            HStack(spacing: 9) {
                Image(systemName: didGenerateProfiles ? "checkmark.seal.fill" : "sparkles")
                    .foregroundStyle(didGenerateProfiles ? Color.green : Color.accentColor)
                Text(personalizationStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isGeneratingProfiles { ProgressView().controlSize(.small) }
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 22) {
            stepHeading(
                "Two permissions. Nothing hidden.",
                "Microphone records your voice. Accessibility detects the hotkey and inserts the finished text."
            )

            VStack(spacing: 11) {
                ForEach(PermissionsService.Kind.allCases) { kind in
                    permissionRow(kind)
                }
            }

            Button {
                permissions.showAccessibilityGuide()
            } label: {
                Label("LazyFlow missing from the Accessibility list?", systemImage: "macwindow.badge.plus")
            }
            .buttonStyle(.link)

            OnboardingCard {
                HStack(spacing: 13) {
                    Image(systemName: "eye.slash.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No screen recording permission")
                            .font(.subheadline.weight(.semibold))
                        Text("LazyFlow does not inspect screenshots, control your browser, or operate your Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 12)
            ZStack {
                Circle()
                    .fill((permissions.coreReady ? Color.green : Color.orange).opacity(0.12))
                    .frame(width: 104, height: 104)
                Image(systemName: permissions.coreReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(permissions.coreReady ? Color.green : Color.orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(permissions.coreReady ? "You’re ready to flow." : "One last check.")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .tracking(-1)
                Text(doneSubtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 500)
            }

            HStack(spacing: 10) {
                summaryCard("Profiles", value: "\(generatedProfileCount)", icon: "app.badge.fill")
                summaryCard("Language", value: appState.dictationLanguage.displayName, icon: "globe")
                summaryCard("Shortcut", value: "Right ⌥", icon: "keyboard")
            }

            OnboardingCard {
                VStack(alignment: .leading, spacing: 9) {
                    Label("Try this", systemImage: "mic.fill")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                    Text("Place your cursor in WhatsApp, Codex, Notes—any text field. Hold Right ⌥, speak naturally, then release.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Tip: say “press enter” at the end to submit, or create reusable phrases under Voice Snippets.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Components

    private func stepHeading(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .tracking(-0.6)
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featurePill(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
            .overlay { Capsule().stroke(Color.primary.opacity(0.06)) }
    }

    private func shortcutRow(_ shortcut: String, _ detail: String) -> some View {
        HStack {
            Text(shortcut)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 145, alignment: .leading)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func appTile(_ app: PopularApp) -> some View {
        let selected = selectedAppIDs.contains(app.bundleIdentifier)
        let active = activeAppID == app.bundleIdentifier
        return Button {
            didGenerateProfiles = false
            generationNote = nil
            if selected {
                selectedAppIDs.remove(app.bundleIdentifier)
                if active { activeAppID = selectedAppIDs.first }
            } else {
                selectedAppIDs.insert(app.bundleIdentifier)
                activeAppID = app.bundleIdentifier
            }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    AppIcon(bundleIdentifier: app.bundleIdentifier, cornerRadius: 6)
                        .frame(width: 28, height: 28)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.45))
                }
                Text(app.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(app.isInstalled ? "Installed" : "Optional")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(app.isInstalled ? Color.green : Color.secondary)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(
                selected ? Color.accentColor.opacity(active ? 0.14 : 0.08) : Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(active ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.055), lineWidth: active ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func preferenceBinding(for app: PopularApp) -> Binding<String> {
        Binding(
            get: { appPreferences[app.bundleIdentifier] ?? app.suggestedPreference },
            set: {
                appPreferences[app.bundleIdentifier] = $0
                didGenerateProfiles = false
                generationNote = nil
            }
        )
    }

    private func presetChip(_ title: String, value: String, app: PopularApp) -> some View {
        Button(title) {
            appPreferences[app.bundleIdentifier] = value
            didGenerateProfiles = false
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func permissionRow(_ kind: PermissionsService.Kind) -> some View {
        let granted = permissions.isGranted(kind)
        return HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill((granted ? Color.green : Color.accentColor).opacity(0.11))
                Image(systemName: kind.systemImage)
                    .font(.title3)
                    .foregroundStyle(granted ? Color.green : Color.accentColor)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title).font(.subheadline.weight(.semibold))
                Text(kind.rationale)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button("Grant") { permissions.request(kind) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(15)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.primary.opacity(0.055))
        }
    }

    private func summaryCard(_ label: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13))
    }

    // MARK: - Footer and actions

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button("Back") { advance(-1) }
                    .buttonStyle(.borderless)
                    .disabled(isGeneratingProfiles)
            }

            Spacer()

            if step == .personalize, !selectedAppIDs.isEmpty, !didGenerateProfiles {
                Button("Skip profiles") { advance(1) }
                    .buttonStyle(.borderless)
                    .disabled(isGeneratingProfiles)
            }

            Button {
                primaryAction()
            } label: {
                HStack(spacing: 7) {
                    if isGeneratingProfiles { ProgressView().controlSize(.small) }
                    Text(primaryTitle)
                    if !isGeneratingProfiles && step != .done {
                        Image(systemName: "arrow.right")
                    }
                }
                .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(isGeneratingProfiles)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var primaryTitle: String {
        switch step {
        case .welcome:     return isReturningUser ? "Review setup" : "Get started"
        case .apiKey:      return "Continue"
        case .personalize:
            if didGenerateProfiles || selectedAppIDs.isEmpty { return "Continue" }
            return "Create \(selectedAppIDs.count) profile\(selectedAppIDs.count == 1 ? "" : "s")"
        case .permissions: return "Continue"
        case .done:        return "Start using LazyFlow"
        }
    }

    private var personalizationStatus: String {
        if isGeneratingProfiles { return "Creating structured styles…" }
        if didGenerateProfiles { return generationNote ?? "Your app profiles are ready. You can refine them anytime." }
        if selectedAppIDs.isEmpty { return "No apps selected. LazyFlow will still create smart defaults as you use it." }
        return "\(selectedAppIDs.count) selected · generation runs once, not during every dictation"
    }

    private var doneSubtitle: String {
        if permissions.coreReady {
            return "Your speech settings and app styles are saved. LazyFlow will keep learning through corrections and protected vocabulary."
        }
        return "Microphone and Accessibility are still required. You can finish now and grant them later from Setup & Permissions."
    }

    private func primaryAction() {
        switch step {
        case .welcome:
            advance(1)
        case .apiKey:
            commitKey()
            advance(1)
        case .personalize:
            if didGenerateProfiles || selectedAppIDs.isEmpty {
                advance(1)
            } else {
                Task { await generateProfiles() }
            }
        case .permissions:
            permissions.refresh()
            advance(1)
        case .done:
            finish()
        }
    }

    private func advance(_ delta: Int) {
        let next = max(0, min(Step.allCases.count - 1, step.rawValue + delta))
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            step = Step(rawValue: next)!
        }
    }

    private func commitKey() {
        let trimmed = groqKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.apiKey = trimmed
        appState.providerStore.setApiKey(trimmed, for: .groq)
    }

    private func generateProfiles() async {
        commitKey()
        isGeneratingProfiles = true
        generationNote = nil
        defer { isGeneratingProfiles = false }

        let groqKey = appState.groqAPIKey
        let config = LLMConfig(
            provider: .groq,
            baseURL: LLMProvider.groq.defaultBaseURL,
            apiKey: groqKey,
            model: LLMProvider.groq.defaultModel
        )
        var count = 0
        var usedFallback = false

        for app in PopularApp.catalog where selectedAppIDs.contains(app.bundleIdentifier) {
            let preference = appPreferences[app.bundleIdentifier] ?? app.suggestedPreference
            let profile: AppProfile
            do {
                profile = try await ProfileGenerationService.generate(
                    for: app,
                    preference: preference,
                    config: config
                )
            } catch {
                usedFallback = true
                profile = ProfileGenerationService.heuristicProfile(for: app, preference: preference)
            }
            appState.profileStore.upsert(profile)
            count += 1
        }

        generatedProfileCount = count
        didGenerateProfiles = true
        generationNote = usedFallback
            ? "Profiles are ready. Smart local defaults replaced one or more unavailable AI generations."
            : "\(count) personalized profile\(count == 1 ? " is" : "s are") ready."
    }

    private func bootstrap() {
        guard !didBootstrap else { return }
        didBootstrap = true
        permissions.refresh()
        groqKey = appState.groqAPIKey

        for app in PopularApp.catalog {
            appPreferences[app.bundleIdentifier] = app.suggestedPreference
        }

        if !isReturningUser {
            let installed = PopularApp.catalog.filter(\.isInstalled)
            let defaults = installed.isEmpty ? Array(PopularApp.catalog.prefix(3)) : Array(installed.prefix(5))
            selectedAppIDs = Set(defaults.map(\.bundleIdentifier))
            activeAppID = defaults.first?.bundleIdentifier
        }

        if !pollingStarted {
            pollingStarted = true
            permissions.startPolling { }
        }
    }

    private func finish() {
        commitKey()
        permissions.stopPolling()
        onFinish()
    }
}

private struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(17)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06))
            }
    }
}
