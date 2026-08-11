import SwiftUI

struct MenuBarIcon: View {
    var appState: AppState  // @Observable — no wrapper needed, SwiftUI tracks automatically
    @State private var pulse = false

    private var isProcessing: Bool { appState.recordingMode == .processing }

    var body: some View {
        ZStack {
            if appState.isRecording {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 18, height: 18)
                    .scaleEffect(pulse ? 1.3 : 0.9)
            }
            Image(systemName: symbol)
                .foregroundStyle(appState.isRecording ? .red : .primary)
                .contentTransition(.symbolEffect(.replace))
                // Transcription runs for a few seconds after the key is released; without
                // this the menu bar looked idle the whole time.
                .symbolEffect(.pulse, isActive: isProcessing)
        }
        // An error is only readable once the popover is open, so badge the icon to show
        // there is something to look at.
        .overlay(alignment: .topTrailing) {
            if appState.errorMessage != nil, !appState.isRecording, !isProcessing {
                Circle()
                    .fill(.orange)
                    .frame(width: 5, height: 5)
                    .offset(x: 1, y: -1)
            }
        }
        .frame(width: 22, height: 22)
        .onChange(of: appState.isRecording) { _, recording in
            if recording {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            } else {
                withAnimation(.default) { pulse = false }
            }
        }
    }

    private var symbol: String {
        if appState.isRecording { return "waveform" }
        if isProcessing         { return "ellipsis" }
        return "mic.fill"
    }
}
