import ActivityGlyph
import SwiftUI

struct KeyboardRootView: View {
    @ObservedObject var model: KeyboardModel
    var nextKeyboard: () -> Void
    var openLazyFlow: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            header

            Group {
                if !model.hasFullAccess {
                    fullAccessMessage
                } else if model.snapshot.isSessionActive {
                    activeKeyboard
                } else {
                    inactiveKeyboard
                }
            }
            .transition(.blurReplace)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            KeyboardBackdrop(tint: statusTint)
                .ignoresSafeArea()
        }
        .animation(.smooth(duration: 0.36), value: model.snapshot.phase)
        .animation(.smooth(duration: 0.3), value: model.hasFullAccess)
    }

    private var header: some View {
        HStack {
            Button(action: nextKeyboard) {
                Image(systemName: "globe")
                    .font(.body.weight(.medium))
                    .frame(width: 36, height: 30)
            }
            .buttonStyle(.glass(.clear.interactive()))
            .accessibilityLabel("Next keyboard")

            Spacer()

            HStack(spacing: 7) {
                Image(systemName: model.snapshot.phase == .recording ? "waveform" : "waveform.badge.mic")
                    .foregroundStyle(statusTint)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(
                        .variableColor.iterative,
                        options: .repeat(.continuous),
                        isActive: model.snapshot.phase == .recording
                    )
                Text("LazyFlow")
                    .font(.subheadline.weight(.bold))
            }

            Spacer()

            Button(action: model.endSession) {
                Image(systemName: "power")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 30)
            }
            .buttonStyle(.glass(.clear.interactive()))
            .disabled(!model.snapshot.isSessionActive)
            .opacity(model.snapshot.isSessionActive ? 1 : 0.24)
            .accessibilityLabel("End voice session")
        }
        .frame(height: 34)
    }

    private var inactiveKeyboard: some View {
        VStack(spacing: 10) {
            ActivityGlyph(
                style: .signal,
                size: .standard,
                speed: 0.72,
                paused: false,
                palette: .tint(ActivityGlyphColor(hex: 0x2875FA)),
                accessibilityLabel: "Waiting for voice session"
            )
            .frame(height: 58)

            VStack(spacing: 2) {
                Text("Start a voice session")
                    .font(.headline)
                Text(model.hasSharedContainer
                     ? "The app listens. This keyboard inserts."
                     : "Unsigned build — reinstall LazyFlow from Xcode")
                    .font(.caption)
                    .foregroundStyle(model.hasSharedContainer ? Color.secondary : Color.orange)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            Button(action: openLazyFlow) {
                HStack(spacing: 8) {
                    if model.isOpeningApp {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "mic.fill")
                    }
                    Text(model.isOpeningApp ? "Opening LazyFlow…" : "Start talking")
                }
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Capsule())
                .glassEffect(
                    .regular.tint(Color.accentColor.opacity(0.14)).interactive(),
                    in: Capsule()
                )
            }
            .buttonStyle(KeyboardPressStyle())
            .disabled(model.isOpeningApp)

            Text(handoffCopy)
                .font(.caption2)
                .foregroundStyle(model.handoffMessage.isEmpty ? Color.secondary : Color.orange)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activeKeyboard: some View {
        VStack(spacing: 9) {
            toneStrip

            HStack(spacing: 10) {
                statusGlyph

                VStack(alignment: .leading, spacing: 1) {
                    Text(statusTitle)
                        .font(.subheadline.weight(.bold))
                        .contentTransition(.opacity)
                    Text(statusDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if model.snapshot.phase == .recording {
                    Button("Cancel", action: model.cancel)
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.glass(.clear.interactive()))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 48)

            FlowWaveform(
                level: model.snapshot.audioLevel,
                isActive: model.snapshot.phase == .recording,
                tint: statusTint,
                barCount: 42
            )
            .frame(height: 42)

            Button(action: model.toggleRecording) {
                Label(actionTitle, systemImage: actionSymbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(statusTint)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .contentShape(Capsule())
                    .glassEffect(
                        .regular.tint(statusTint.opacity(0.14)).interactive(),
                        in: Capsule()
                    )
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(KeyboardPressStyle())
            .disabled(!canRecord)
            .opacity(canRecord ? 1 : 0.5)
            .accessibilityHint(actionHint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var toneStrip: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(MobileTone.allCases) { tone in
                        let isSelected = model.snapshot.tone == tone

                        Button {
                            model.selectTone(tone)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: tone.symbol)
                                Text(tone.compactTitle)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? tone.tint : Color.primary.opacity(0.72))
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .contentShape(Capsule())
                            .glassEffect(
                                isSelected
                                    ? .regular.tint(tone.tint.opacity(0.16)).interactive()
                                    : .clear.interactive(),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(KeyboardPressStyle())
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 1, for: .scrollContent)
        .frame(height: 34)
    }

    private var statusGlyph: some View {
        ActivityGlyph(
            style: glyphStyle,
            size: .standard,
            speed: model.snapshot.phase == .recording ? 1.12 : 0.82,
            paused: false,
            palette: .tint(glyphColor),
            accessibilityLabel: statusTitle
        )
        .id(glyphStyle)
        .scaleEffect(0.68)
        .frame(width: 46, height: 46)
        .transition(.scale.combined(with: .opacity))
    }

    private var fullAccessMessage: some View {
        VStack(spacing: 8) {
            ActivityGlyph(
                style: .network,
                size: .standard,
                speed: 0.7,
                palette: .tint(ActivityGlyphColor(hex: 0xE88822)),
                accessibilityLabel: "Keyboard bridge disconnected"
            )
            .frame(height: 58)

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

    private var handoffCopy: String {
        if !model.handoffMessage.isEmpty {
            return model.handoffMessage
        }
        return "Start in LazyFlow, then return to your text field."
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

    private var actionHint: String {
        model.snapshot.phase == .recording
            ? "Stops recording and inserts the finished text"
            : "Starts recording in the LazyFlow app"
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
        case .ready: .signal
        case .off, .failed: .pulse
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

private struct KeyboardBackdrop: View {
    var tint: Color

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            LinearGradient(
                colors: [
                    tint.opacity(0.08),
                    Color.clear,
                    Color(.systemBackground).opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct KeyboardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
