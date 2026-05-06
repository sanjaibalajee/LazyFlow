import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RecordButton()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            if let error = appState.errorMessage {
                ErrorBanner(message: error) { appState.clearError() }
            }

            Divider()

            recentTranscripts
                .padding(.vertical, 4)

            Divider()

            footerButtons
                .padding(.vertical, 4)
        }
        .frame(width: 300)
    }

    // MARK: - Recent Transcripts

    @ViewBuilder
    private var recentTranscripts: some View {
        if appState.history.isEmpty {
            Text("No transcripts yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        } else {
            ForEach(appState.history.prefix(3)) { entry in
                MenuBarTranscriptRow(entry: entry)
            }
        }
    }

    // MARK: - Footer

    private var footerButtons: some View {
        VStack(spacing: 0) {
            MenuBarButton(label: "Open LazyFlow", icon: "arrow.up.left.and.arrow.down.right") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            MenuBarButton(label: "Settings", icon: "gear") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
            MenuBarButton(label: "Quit LazyFlow", icon: "power") {
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - Record Button

struct RecordButton: View {
    @Environment(AppState.self) private var appState

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
                        .frame(width: 32, height: 32)
                    if isProcessing {
                        ProgressView().scaleEffect(0.6).tint(.white)
                    } else {
                        Image(systemName: appState.isRecording ? "stop.fill" : "mic.fill")
                            .foregroundStyle(.white)
                            .font(.system(size: 13, weight: .semibold))
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
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.7 : 1)
    }

    private var buttonColor: Color {
        if isProcessing    { return .secondary }
        if appState.isRecording { return .red }
        return .accentColor
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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .font(.caption)
                    .lineLimit(2)
                if let app = entry.appName {
                    Text(app)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Copy to clipboard")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}

// MARK: - Error Banner

struct ErrorBanner: View {
    let message: String
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

// MARK: - Menu Bar Button

struct MenuBarButton: View {
    let label: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(label)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
