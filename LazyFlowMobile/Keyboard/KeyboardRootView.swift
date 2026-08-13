import ActivityGlyph
import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardModel
    var nextKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            topBar

            if model.hasFullAccess {
                activeKeyboard
                    .transition(.opacity)
            } else {
                fullAccessMessage
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .animation(.smooth(duration: 0.3), value: model.hasFullAccess)
        .animation(.smooth(duration: 0.25), value: model.snapshot.phase)
    }

    private var topBar: some View {
        HStack {
            Button(action: nextKeyboard) {
                Image(systemName: "globe")
                    .font(.body.weight(.medium))
                    .frame(width: 40, height: 34)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next keyboard")

            Spacer()

            HStack(spacing: 7) {
                Image(systemName: "waveform")
                    .foregroundStyle(model.snapshot.tone.tint)
                Text("LazyFlow")
                    .font(.subheadline.weight(.bold))
            }

            Spacer()

            Button(action: model.endSession) {
                Image(systemName: "power")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 40, height: 34)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!model.snapshot.isSessionActive)
            .opacity(model.snapshot.isSessionActive ? 1 : 0.35)
            .accessibilityLabel("End voice session")
        }
    }

    private var activeKeyboard: some View {
        VStack(spacing: 10) {
            toneStrip

            HStack(spacing: 14) {
                statusGlyph

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                recordButton
            }
            .padding(.horizontal, 14)
            .frame(height: 76)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            FlowWaveform(
                level: model.snapshot.audioLevel,
                isActive: model.snapshot.phase == .recording,
                tint: statusTint,
                barCount: 34
            )
            .frame(height: 34)
            .padding(.horizontal, 8)
        }
    }

    private var toneStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(MobileTone.allCases) { tone in
                    Button {
                        model.selectTone(tone)
                    } label: {
                        Text(tone.compactTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(model.snapshot.tone == tone ? .white : .primary)
                            .padding(.horizontal, 12)
                            .frame(height: 31)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(model.snapshot.tone == tone ? tone.tint : Color.primary.opacity(0.065))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var statusGlyph: some View {
        ActivityGlyph(
            style: glyphStyle,
            size: .inline,
            speed: 1.1,
            paused: model.snapshot.phase == .off || model.snapshot.phase == .ready,
            palette: .tint(glyphColor),
            accessibilityLabel: statusTitle
        )
        .frame(width: 34, height: 34)
        .background(statusTint.opacity(0.10), in: Circle())
    }

    private var recordButton: some View {
        Button(action: model.toggleRecording) {
            Image(systemName: model.snapshot.phase == .recording ? "stop.fill" : "mic.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(statusTint, in: Circle())
                .shadow(color: statusTint.opacity(0.24), radius: 8, y: 4)
        }
        .buttonStyle(KeyboardPressStyle())
        .disabled(!canRecord)
        .opacity(canRecord ? 1 : 0.38)
        .accessibilityLabel(model.snapshot.phase == .recording ? "Stop recording" : "Start recording")
    }

    private var fullAccessMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.open")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("Allow Full Access")
                .font(.headline)
            Text("In Settings, enable Full Access for LazyFlow so this keyboard can talk to the app. Audio stays in the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 330)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var canRecord: Bool {
        model.snapshot.phase == .ready
            || model.snapshot.phase == .recording
            || model.snapshot.phase == .resultReady
    }

    private var statusTitle: String {
        guard model.snapshot.isSessionActive else { return "Start in the LazyFlow app" }
        return switch model.snapshot.phase {
        case .off: "Start in the LazyFlow app"
        case .preparing: "Getting ready…"
        case .ready: "Tap to speak"
        case .recording: "Listening…"
        case .processing: "Making it flow…"
        case .resultReady: "Inserting…"
        case .failed: "Open LazyFlow to retry"
        }
    }

    private var statusDetail: String {
        guard model.snapshot.isSessionActive else { return "Then come back to this keyboard" }
        return switch model.snapshot.phase {
        case .recording: "Tap stop when you’re done"
        case .processing: "On-device transcription"
        case .failed: model.snapshot.errorMessage
        default: model.snapshot.tone.subtitle
        }
    }

    private var statusTint: Color {
        switch model.snapshot.phase {
        case .recording: .red
        case .processing: .purple
        case .failed: .orange
        default: model.snapshot.tone.tint
        }
    }

    private var glyphStyle: ActivityGlyphStyle {
        switch model.snapshot.phase {
        case .recording: .signal
        case .processing: .compose
        case .preparing: .focus
        case .resultReady: .resolve
        case .failed: .pulse
        case .off, .ready: .weave
        }
    }

    private var glyphColor: ActivityGlyphColor {
        switch model.snapshot.phase {
        case .recording: ActivityGlyphColor(hex: 0xF04452)
        case .processing: ActivityGlyphColor(hex: 0x7847F5)
        case .failed: ActivityGlyphColor(hex: 0xE88822)
        default: ActivityGlyphColor(hex: 0x2875FA)
        }
    }
}

private struct KeyboardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
