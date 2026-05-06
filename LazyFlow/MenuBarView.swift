import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecordButton()
                .padding(.horizontal, 8)
                .padding(.vertical, 8)

            if let error = appState.errorMessage {
                ErrorBanner(message: error) { appState.clearError() }
            }

            Divider()

            recentTranscripts

            Divider()

            footerButtons
        }
        .frame(width: 300)
        .padding(.vertical, 4)
    }

    // MARK: - Recent Transcripts

    @ViewBuilder
    private var recentTranscripts: some View {
        if appState.history.isEmpty {
            Text("No transcripts yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        } else {
            VStack(spacing: 0) {
                ForEach(appState.history.prefix(3)) { entry in
                    MenuBarTranscriptRow(entry: entry)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        VStack(spacing: 0) {
            MenuBarActionRow(label: "Open LazyFlow", icon: "macwindow") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            MenuBarActionRow(label: "Settings", icon: "gear") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            MenuBarActionRow(label: "Quit LazyFlow", icon: "power", isDestructive: true) {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Record Button

struct RecordButton: View {
    @Environment(AppState.self) private var appState
    @State private var isHovered = false

    private var isProcessing: Bool { appState.recordingMode == .processing }

    var body: some View {
        Button {
            if appState.isRecording { appState.stopRecording() }
            else if !isProcessing   { appState.startRecording() }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(buttonColor)
                        .frame(width: 30, height: 30)
                    if isProcessing {
                        ProgressView().scaleEffect(0.55).tint(.white)
                    } else {
                        Image(systemName: appState.isRecording ? "stop.fill" : "mic.fill")
                            .foregroundStyle(.white)
                            .font(.system(size: 12, weight: .semibold))
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(labelTitle)
                        .font(.system(size: 13, weight: .semibold))
                    Text(labelSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                isHovered && !isProcessing
                    ? Color.primary.opacity(0.07)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.65 : 1)
        .onHover { isHovered = $0 }
    }

    private var buttonColor: Color {
        if isProcessing         { return Color(nsColor: .systemGray) }
        if appState.isRecording { return .red }
        return Color.accentColor
    }

    private var labelTitle: String {
        if isProcessing         { return "Processing…" }
        if appState.isRecording { return "Recording…" }
        return "Start Recording"
    }

    private var labelSubtitle: String {
        if isProcessing         { return "Transcribing your audio" }
        if appState.isRecording { return "Click to stop" }
        return "or hold Right ⌥"
    }
}

// MARK: - Transcript Row

struct MenuBarTranscriptRow: View {
    let entry: TranscriptEntry
    @State private var isHovered = false
    @State private var copied    = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    if let app = entry.appName {
                        Text(app)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }
                    Text(entry.date.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
            }

            Spacer(minLength: 4)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(copied ? Color.green : Color.secondary)
                    .frame(width: 20, height: 20)
                    .opacity(isHovered || copied ? 1 : 0)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            isHovered ? Color.primary.opacity(0.06) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .padding(.horizontal, 4)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message:   String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .padding(.top, 1)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.08))
    }
}

// MARK: - Action Row (hover-aware menu item)

struct MenuBarActionRow: View {
    let label:         String
    let icon:          String
    var isDestructive: Bool = false
    let action:        () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 16, alignment: .center)
                    .foregroundStyle(
                        isHovered
                            ? (isDestructive ? Color.red : Color.primary)
                            : Color.secondary
                    )
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(
                        isDestructive && isHovered ? Color.red : Color.primary
                    )
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isHovered
                    ? (isDestructive ? Color.red.opacity(0.1) : Color.primary.opacity(0.07))
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { isHovered = $0 }
    }
}
