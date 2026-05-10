import SwiftUI
import Charts

// MARK: - Panel

struct SystemMonitorPanel: View {
    @Environment(SystemMonitor.self) private var m

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            gpuCard
            cpuCard
            ramCard
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 14)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - GPU Card
    private var gpuCard: some View {
        MonitorCard(
            title: "GPU",
            icon: "cpu",
            color: .blue,
            primaryText: pct(m.gpuUtil),
            fraction: m.gpuUtil,
            history: m.gpuHistory
        ) {
            HStack(spacing: 12) {
                SubBadge(label: "Render", value: pct(m.gpuRender))
                SubBadge(label: "Tiler",  value: pct(m.gpuTiler))
                Spacer()
            }
        }
    }

    // MARK: - CPU Card
    private var cpuCard: some View {
        MonitorCard(
            title: "CPU",
            icon: "memorychip",
            color: .green,
            primaryText: pct(m.cpuTotal),
            fraction: m.cpuTotal,
            history: m.cpuHistory
        ) {
            HStack(spacing: 3) {
                ForEach(m.cpuCores.indices, id: \.self) { i in
                    CoreBar(fraction: m.cpuCores[i], color: .green)
                }
                Spacer()
            }
        }
    }

    // MARK: - RAM Card
    private var ramCard: some View {
        let frac  = m.ramTotal > 0 ? min(1, m.ramUsed / m.ramTotal) : 0
        let color: Color = frac > 0.88 ? .orange : frac > 0.72 ? .yellow : .purple
        let usedGB  = m.ramUsed  / 1_073_741_824
        let totalGB = m.ramTotal / 1_073_741_824
        let label   = String(format: "%.1f / %.0f GB", usedGB, totalGB)

        return MonitorCard(
            title: "RAM",
            icon: "internaldrive",
            color: color,
            primaryText: label,
            fraction: frac,
            history: m.ramHistory
        ) {
            HStack(spacing: 12) {
                SubBadge(label: "Wired", value: gbString(m.ramWired))
                SubBadge(label: "Cmp",   value: gbString(m.ramCompressed))
                Spacer()
            }
        }
    }

    // MARK: - Helpers
    private func pct(_ v: Double) -> String { "\(Int(v * 100))%" }
    private func gbString(_ bytes: Double) -> String {
        bytes >= 1_073_741_824
            ? String(format: "%.1f GB", bytes / 1_073_741_824)
            : String(format: "%.0f MB", bytes / 1_048_576)
    }
}

// MARK: - MonitorCard

private struct MonitorCard<Footer: View>: View {
    let title:      String
    let icon:       String
    let color:      Color
    let primaryText: String
    let fraction:   Double
    let history:    [Double]
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Spacer()
                Text(primaryText)
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.3), value: primaryText)
            }

            // Progress bar
            Capsule()
                .fill(color.opacity(0.10))
                .frame(height: 5)
                .overlay(alignment: .leading) {
                    GeometryReader { g in
                        let w = max(0, g.size.width) * CGFloat(max(0, min(1, fraction)))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [color.opacity(0.55), color]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: w)
                            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: fraction)
                    }
                }
                .clipped()
                .padding(.top, 10)

            // Sparkline
            sparkline
                .padding(.top, 8)

            // Footer sub-metrics
            footer()
                .padding(.top, 8)
        }
        .padding(12)
        .frame(minWidth: 0, maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(color.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 11)
                        .stroke(color.opacity(0.13), lineWidth: 1)
                )
        )
    }

    private var sparkline: some View {
        let pts = history.enumerated().map { HistPoint(i: $0.offset, v: $0.element) }
        return Chart(pts) { p in
            AreaMark(x: .value("t", p.i), y: .value("v", p.v))
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.35), color.opacity(0.03)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            LineMark(x: .value("t", p.i), y: .value("v", p.v))
                .foregroundStyle(color.opacity(0.75))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartYScale(domain: 0...1)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { $0.frame(height: 30) }
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: 30)
        .clipped()
    }
}

// MARK: - Sub-views

private struct HistPoint: Identifiable {
    var id: Int { i }
    let i: Int
    let v: Double
}

private struct SubBadge: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct CoreBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.12))
            RoundedRectangle(cornerRadius: 2)
                .fill(color.opacity(0.72))
                .frame(height: max(2, 14 * CGFloat(fraction)))
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: fraction)
        }
        .frame(width: 6, height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}
