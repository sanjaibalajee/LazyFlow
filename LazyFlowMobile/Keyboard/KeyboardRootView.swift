import ActivityGlyph
import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardModel
    var nextKeyboard: () -> Void
    var openLazyFlow: () -> Void

    var body: some View {
        VStack(spacing: 9) {
            header

            if !model.hasFullAccess {
                fullAccessMessage
            } else if model.snapshot.isSessionActive {
                activeKeyboard
            } else {
                inactiveKeyboard
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .animation(.smooth(duration: 0.28), value: model.snapshot.phase)
        .animation(.smooth(duration: 0.28), value: model.hasFullAccess)
    }

    private var header: some View {
        HStack {
            Button(action: nextKeyboard) {
                Image(systemName: "globe")
                    .font(.body.weight(.medium))
                    .frame(width: 40, height: 34)
                    .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
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
                    .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!model.snapshot.isSessionActive)
            .opacity(model.snapshot.isSessionActive ? 1 : 0.28)
            .accessibilityLabel("End voice session")
        }
    }

    private var inactiveKeyboard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ActivityGlyph(
                    style: .pulse,
                    size: .inline,
                    paused: true,
                    palette: .tint(ActivityGlyphColor(hex: 0x2875FA)),
                    accessibilityLabel: "Waiting for voice session"
                )
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.10), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Start a voice session")
                        .font(.headline)
                    Text(model.hasSharedContainer
                         ? "LazyFlow needs the app to own the microphone"
                         : "Bridge unavailable — check LazyFlow Settings")
                        .font(.caption)
                        .foregroundStyle(model.hasSharedContainer ? Color.secondary : Color.orange)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: openLazyFlow) {
                HStack(spacing: 8) {
                    if model.isOpeningApp {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "mic.fill")
                    }
                    Text("Start talking")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            }
            .buttonStyle(KeyboardPressStyle())
            .disabled(model.isOpeningApp)

            if !model.handoffMessage.isEmpty {
                Text(model.handoffMessage)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            } else {
                Text("LazyFlow will open. Start the session, then return to your text field.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var activeKeyboard: some View {
        VStack(spacing: 9) {
            toneStrip

            VStack(spacing: 7) {
                HStack(spacing: 10) {
                    statusGlyph
                    VStack(alignment: .leading, spacing: 1) {
                        Text(statusTitle)
                            .font(.subheadline.weight(.bold))
                        Text(statusDetail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if model.snapshot.phase == .recording {
                        Button("Cancel", action: model.cancel)
                            .font(.caption.weight(.semibold))
                    }
                }

                FlowWaveform(
                    level: model.snapshot.audioLevel,
                    isActive: model.snapshot.phase == .recording,
                    tint: statusTint,
                    barCount: 38
                )
                .frame(height: 24)

                Button(action: model.toggleRecording) {
                    Label(actionTitle, systemImage: actionSymbol)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 43)
                        .background(statusTint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(KeyboardPressStyle())
                .disabled(!canRecord)
                .opacity(canRecord ? 1 : 0.55)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var toneStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(MobileTone.allCases) { tone in
                    Button {
                        model.selectTone(tone)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tone.symbol)
                            Text(tone.compactTitle)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(model.snapshot.tone == tone ? .white : .primary)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background {
                            Capsule(style: .continuous)
                                .fill(model.snapshot.tone == tone ? tone.tint : Color.primary.opacity(0.06))
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
            speed: model.snapshot.phase == .recording ? 1.15 : 0.9,
            paused: model.snapshot.phase == .ready,
            palette: .tint(glyphColor),
            accessibilityLabel: statusTitle
        )
        .frame(width: 34, height: 34)
        .background(statusTint.opacity(0.10), in: Circle())
    }

    private var fullAccessMessage: some View {
        VStack(spacing: 7) {
            Image(systemName: "lock.open")
                .font(.title3)
                .foregroundStyle(.orange)
            Text("Allow Full Access")
                .font(.headline)
            Text("Enable it for LazyFlow in Keyboard Settings. It is used only for the private app bridge.")
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

    private var actionTitle: String {
        switch model.snapshot.phase {
        case .recording: "Stop and insert"
        case .processing: "Making it flow…"
        case .resultReady: "Inserting…"
        default: "Start talking"
        }
    }

    private var actionSymbol: String {
        switch model.snapshot.phase {
        case .recording: "stop.fill"
        case .processing: "wand.and.sparkles"
        case .resultReady: "arrow.turn.down.left"
        default: "mic.fill"
        }
    }

    private var statusTitle: String {
        switch model.snapshot.phase {
        case .preparing: "Getting ready…"
        case .ready: "Ready to listen"
        case .recording: "Listening…"
        case .processing: "Making it flow…"
        case .resultReady: "Inserting at the cursor…"
        case .failed: "Open LazyFlow to retry"
        case .off: "Start in LazyFlow"
        }
    }

    private var statusDetail: String {
        switch model.snapshot.phase {
        case .recording: "Speak naturally, then tap stop"
        case .processing: "Transcribing and applying your tone"
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
        case .off, .ready, .failed: .pulse
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
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
