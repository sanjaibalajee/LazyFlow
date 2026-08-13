import ActivityGlyph
import SwiftUI
import UIKit

struct RootView: View {
    @ObservedObject var session: DictationSessionController

    @AppStorage("hasCompletedMobileOnboarding") private var hasCompletedOnboarding = false
    @State private var showingSetup = false
    @State private var selectedTab = 0
#if DEBUG
    @State private var showingKeyboardPreview = false
#endif

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainContent
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                OnboardingView {
                    withAnimation(.smooth(duration: 0.45)) {
                        hasCompletedOnboarding = true
                        showingSetup = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingSetup) {
            KeyboardSetupView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
#if DEBUG
        .sheet(isPresented: $showingKeyboardPreview) {
            KeyboardPreviewHost()
                .presentationDetents([.height(290)])
                .presentationDragIndicator(.visible)
        }
#endif
        .onOpenURL { url in
            guard url.scheme == "lazyflow" else { return }
            switch url.host {
            case "talk":
                selectedTab = 0
            case "start":
                selectedTab = 0
                Task { await session.startSession() }
            case "history":
                selectedTab = 1
            case "settings":
                selectedTab = 2
            case "setup":
                selectedTab = 2
                showingSetup = true
#if DEBUG
            case "keyboard-preview":
                showingKeyboardPreview = true
#endif
            default:
                break
            }
        }
#if DEBUG
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-showKeyboardPreview") {
                showingKeyboardPreview = true
            }
            if arguments.contains("-showKeyboardSetup") {
                showingSetup = true
            }
        }
#endif
    }

    private var mainContent: some View {
        TabView(selection: $selectedTab) {
            dictationContent
                .tag(0)
                .tabItem { Label("Talk", systemImage: "waveform") }

            HistoryView(store: session.history)
                .tag(1)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            SettingsView(
                settings: session.settings,
                hasSharedContainer: session.hasSharedContainer,
                showKeyboardSetup: { showingSetup = true }
            )
            .tag(2)
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(session.tone.tint)
    }

    private var dictationContent: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    sessionCard
                    toneCard
                    privacyNote
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(background)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LazyFlow")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("Voice keyboard")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label(
                session.settings.transcriptionProvider == .apple ? "On device" : "Groq",
                systemImage: session.settings.transcriptionProvider == .apple ? "iphone" : "cloud"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(.thinMaterial, in: Capsule())
        }
        .padding(.top, 12)
    }

    private var sessionCard: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(statusTint.opacity(0.10))
                    .frame(width: 108, height: 108)
                    .scaleEffect(session.isRecording ? 1.08 : 1)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: session.isRecording)

                ActivityGlyph(
                    style: glyphStyle,
                    size: .standard,
                    speed: session.isRecording ? 1.15 : 0.85,
                    paused: session.phase == .off || session.phase == .ready,
                    palette: .tint(glyphColor),
                    accessibilityLabel: statusTitle
                )
            }

            VStack(spacing: 7) {
                Text(statusTitle)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .contentTransition(.numericText())
                Text(statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            FlowWaveform(
                level: session.level,
                isActive: session.isRecording,
                tint: statusTint
            )
            .opacity(session.isSessionActive ? 1 : 0.55)

            Button {
                Task {
                    if session.isSessionActive {
                        session.endSession()
                    } else {
                        await session.startSession()
                    }
                }
            } label: {
                Label(
                    session.isSessionActive ? "End voice session" : "Start voice session",
                    systemImage: session.isSessionActive ? "stop.fill" : "mic.fill"
                )
            }
            .buttonStyle(SessionActionButtonStyle(active: session.isSessionActive, tint: statusTint))
            .disabled(session.phase == .preparing || session.phase == .processing)
            .sensoryFeedback(.impact(weight: .medium), trigger: session.isSessionActive)

            if session.phase == .failed {
                HStack(spacing: 18) {
                    Button("Try again") { Task { await session.retry() } }
                    if session.settings.needsGroqKey && !session.settings.hasGroqKey {
                        Button("Open Settings") { selectedTab = 2 }
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.055))
        }
    }

    private var toneCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Tone", systemImage: session.tone.symbol)
                    .font(.headline)
                Spacer()
                Text(session.tone.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            TonePicker(selection: $session.tone)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var privacyNote: some View {
        Label(
            session.isSessionActive
                ? "The microphone remains active while this session is on. iOS shows its orange privacy indicator."
                : privacySummary,
            systemImage: session.isSessionActive ? "mic.badge.plus" : "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }

    private var background: some View {
        ZStack {
            Color(.systemGroupedBackground)
            RadialGradient(
                colors: [statusTint.opacity(0.10), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 320
            )
        }
        .ignoresSafeArea()
        .animation(.smooth, value: session.phase)
    }

    private var statusTitle: String {
        switch session.phase {
        case .off: "Ready when you are"
        case .preparing: "Preparing…"
        case .ready: "Voice session is on"
        case .recording: "Listening…"
        case .processing: "Making it flow…"
        case .resultReady: "Sent to your keyboard"
        case .failed: "Something interrupted the flow"
        }
    }

    private var statusDetail: String {
        switch session.phase {
        case .off: "Start a session, then switch to LazyFlow from any text field."
        case .preparing: "Getting the microphone and selected speech model ready."
        case .ready: "You can leave this app. Tap the mic from the LazyFlow keyboard."
        case .recording: "Speak naturally. Tap stop in the keyboard when you’re done."
        case .processing: "Transcribing and applying your \(session.tone.title.lowercased()) tone."
        case .resultReady: "Your words will appear at the cursor."
        case .failed: session.errorMessage
        }
    }

    private var glyphStyle: ActivityGlyphStyle {
        switch session.phase {
        case .recording: .signal
        case .processing: .compose
        case .preparing: .focus
        case .resultReady: .resolve
        case .failed: .pulse
        case .off, .ready: .pulse
        }
    }

    private var statusTint: Color {
        switch session.phase {
        case .recording: .red
        case .processing: .purple
        case .failed: .orange
        default: session.tone.tint
        }
    }

    private var glyphColor: ActivityGlyphColor {
        switch session.phase {
        case .recording: ActivityGlyphColor(hex: 0xF04452)
        case .processing: ActivityGlyphColor(hex: 0x7847F5)
        case .failed: ActivityGlyphColor(hex: 0xE88822)
        default: ActivityGlyphColor(hex: 0x2875FA)
        }
    }

    private var privacySummary: String {
        session.settings.needsGroqKey
            ? "Cloud is enabled for selected processing steps. History stays on this iPhone."
            : "On-device transcription and rewriting. No account or API key."
    }
}

#if DEBUG
private struct KeyboardPreviewHost: View {
    @StateObject private var model = KeyboardModel(
        hasFullAccess: true,
        sharedContainerAvailable: true,
        insertText: { _ in }
    )

    var body: some View {
        KeyboardRootView(
            model: model,
            nextKeyboard: {},
            openLazyFlow: {}
        )
    }
}
#endif

private struct SessionActionButtonStyle: ButtonStyle {
    let active: Bool
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(active ? tint : .white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(active ? tint.opacity(0.12) : tint, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

private struct KeyboardSetupView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    setupStep(1, title: "Add the keyboard", detail: "Open Settings › General › Keyboard › Keyboards › Add New Keyboard, then choose LazyFlow.")
                    setupStep(2, title: "Allow Full Access", detail: "Full Access lets the keyboard exchange commands and finished text with the LazyFlow app. Audio never enters the keyboard extension.")
                    setupStep(3, title: "Start a voice session", detail: "Return here and start a session. In any text field, hold the globe and choose LazyFlow.")

                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .buttonStyle(PrimaryActionButtonStyle())
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 42)
            }
            .navigationTitle("Keyboard setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func setupStep(_ number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
