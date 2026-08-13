import SwiftUI

struct FlowWaveform: View {
    var level: Double
    var isActive: Bool
    var tint: Color
    var barCount = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: !isActive || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate

            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(tint.opacity(isActive ? 0.9 : 0.28))
                        .frame(width: 3, height: height(for: index, at: time))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .animation(.smooth(duration: 0.22), value: level)
        }
        .accessibilityHidden(true)
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        guard isActive else {
            return CGFloat(5 + (index % 3) * 2)
        }

        let normalized = max(0.12, min(level, 1))
        let center = Double(barCount - 1) / 2
        let distance = abs(Double(index) - center) / max(center, 1)
        let envelope = 1 - (distance * 0.45)
        let primary = sin(time * 7.2 + Double(index) * 0.71)
        let secondary = sin(time * 4.1 - Double(index) * 0.39)
        let movement = 0.52 + 0.30 * primary + 0.18 * secondary
        return CGFloat(7 + max(0.08, movement) * normalized * envelope * 35)
    }
}
