import SwiftUI

struct MenuBarIcon: View {
    var appState: AppState  // @Observable — no wrapper needed, SwiftUI tracks automatically
    @State private var pulse = false

    var body: some View {
        ZStack {
            if appState.isRecording {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 18, height: 18)
                    .scaleEffect(pulse ? 1.3 : 0.9)
            }
            Image(systemName: appState.isRecording ? "waveform" : "mic.fill")
                .foregroundStyle(appState.isRecording ? .red : .primary)
                .contentTransition(.symbolEffect(.replace))
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
}
