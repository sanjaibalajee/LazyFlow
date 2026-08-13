import SwiftUI

/// A live, level-driven voice trace drawn with the same lightweight Canvas
/// approach as ActivityGlyph. The motion is decorative only; amplitude comes
/// from the app's microphone meter through the shared dictation snapshot.
struct FlowWaveform: View {
    var level: Double
    var isActive: Bool
    var tint: Color
    var barCount = 24

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1 / 45,
                paused: !isActive || reduceMotion
            )
        ) { timeline in
            Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: false) { context, size in
                let time = reduceMotion ? 0.6 : timeline.date.timeIntervalSinceReferenceDate
                let points = samples(in: size, time: time)
                let centerY = size.height / 2

                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: centerY))
                baseline.addLine(to: CGPoint(x: size.width, y: centerY))
                context.stroke(
                    baseline,
                    with: .color(tint.opacity(isActive ? 0.10 : 0.07)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )

                var trace = Path()
                if let first = points.first {
                    trace.move(to: first)
                    for point in points.dropFirst() {
                        trace.addLine(to: point)
                    }
                }

                context.stroke(
                    trace,
                    with: .linearGradient(
                        Gradient(colors: [
                            tint.opacity(0.22),
                            tint.opacity(isActive ? 0.95 : 0.30),
                            tint.opacity(0.22)
                        ]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: 0)
                    ),
                    style: StrokeStyle(
                        lineWidth: isActive ? 2.2 : 1.5,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                for (index, point) in points.enumerated() where index.isMultiple(of: 4) {
                    let envelope = sampleEnvelope(at: index, count: points.count)
                    let radius = isActive ? 1.1 + envelope * 0.7 : 0.9
                    let rect = CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(tint.opacity(isActive ? 0.78 : 0.25))
                    )
                }
            }
        }
        .animation(.smooth(duration: 0.18), value: level)
        .accessibilityHidden(true)
    }

    private func samples(in size: CGSize, time: TimeInterval) -> [CGPoint] {
        let count = max(barCount, 12)
        let drive = isActive ? 0.12 + min(max(level, 0), 1) * 0.88 : 0.035
        let availableAmplitude = max((size.height / 2) - 3, 1)

        return (0..<count).map { index in
            let progress = Double(index) / Double(count - 1)
            let envelope = sampleEnvelope(at: index, count: count)
            let primary = sin(time * 8.2 + progress * .pi * 7.0)
            let secondary = sin(time * 5.1 - progress * .pi * 11.0) * 0.36
            let detail = sin(time * 12.7 + progress * .pi * 3.0) * 0.12
            let motion = primary + secondary + detail
            let y = (size.height / 2) + CGFloat(motion * drive * envelope) * availableAmplitude

            return CGPoint(
                x: size.width * CGFloat(progress),
                y: y
            )
        }
    }

    private func sampleEnvelope(at index: Int, count: Int) -> Double {
        let progress = Double(index) / Double(max(count - 1, 1))
        return pow(sin(progress * .pi), 0.72)
    }
}
