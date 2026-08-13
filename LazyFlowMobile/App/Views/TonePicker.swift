import SwiftUI

struct TonePicker: View {
    @Binding var selection: MobileTone
    var compact = false

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(MobileTone.allCases) { tone in
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
                        .foregroundStyle(selection == tone ? .white : .primary)
                        .padding(.horizontal, compact ? 12 : 14)
                        .frame(height: compact ? 34 : 38)
                        .background {
                            Capsule(style: .continuous)
                                .fill(selection == tone ? tone.tint : Color.primary.opacity(0.065))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tone.title) tone")
                    .accessibilityAddTraits(selection == tone ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}
