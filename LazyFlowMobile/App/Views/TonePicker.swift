import SwiftUI

struct TonePicker: View {
    @Binding var selection: MobileTone
    var compact = false

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: 9) {
                HStack(spacing: 9) {
                    ForEach(MobileTone.allCases) { tone in
                        let isSelected = selection == tone

                        Button {
                            withAnimation(.snappy(duration: 0.28)) {
                                selection = tone
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tone.symbol)
                                    .font(.caption.weight(.semibold))
                                Text(compact ? tone.compactTitle : tone.title)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isSelected ? tone.tint : Color.primary.opacity(0.72))
                            .padding(.horizontal, compact ? 12 : 14)
                            .frame(height: compact ? 34 : 38)
                            .contentShape(Capsule())
                            .glassEffect(
                                isSelected
                                    ? .regular.tint(tone.tint.opacity(0.15)).interactive()
                                    : .clear.interactive(),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(TonePressStyle())
                        .accessibilityLabel("\(tone.title) tone")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct TonePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}
