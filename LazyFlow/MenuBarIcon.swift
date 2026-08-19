import SwiftUI

struct MenuBarIcon: View {
    var appState: AppState  // @Observable — no wrapper needed, SwiftUI tracks automatically
    @State private var pulse = false
    private var isProcessing: Bool { appState.recordingMode == .processing }

    var body: some View {
        ZStack {
            if appState.isRecording {
                Circle()
                    .stroke(Color.red.opacity(0.35), lineWidth: 2)
                    .frame(width: 19, height: 19)
                    .scaleEffect(pulse ? 1.15 : 0.9)
            }

            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(appState.isRecording ? Color.red : Color.primary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: isProcessing)
        }
        .overlay(alignment: .topTrailing) {
            if appState.errorMessage != nil, !appState.isRecording, !isProcessing {
                Circle()
                    .fill(.orange)
                    .frame(width: 5, height: 5)
                    .offset(x: 1, y: -1)
            }
        }
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .accessibilityLabel(appState.isRecording ? "LazyFlow recording" : "LazyFlow")
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
        if appState.isRecording { return "waveform.circle.fill" }
        if isProcessing { return "ellipsis.circle" }
        return "waveform.circle"
    }
}
