import SwiftUI

struct GPUCard: View {
    @ObservedObject var gpu: GPUMonitor

    private let accent = Theme.gpu

    private var vramFraction: Double {
        gpu.vramTotal > 0 ? gpu.vramUsed / gpu.vramTotal : 0
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                CardHeader(icon: "display",
                           title: "GPU",
                           accent: accent,
                           trailing: gpu.isAvailable ? Formatters.percent(gpu.utilization) : nil,
                           trailingColor: Theme.semantic(for: gpu.utilization))

                if !gpu.isAvailable {
                    Text(loc: "No discrete GPU metrics on this device.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                } else {
                MetricChart(values: gpu.history, maxValue: 1, color: accent)
                    .frame(height: 48)

                HStack(spacing: 14) {
                    RingGauge(fraction: vramFraction,
                              color: accent,
                              lineWidth: 9,
                              value: Formatters.percent(vramFraction),
                              caption: "VRAM")
                        .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 7) {
                        legendRow("Chip", gpu.name)
                        legendRow("VRAM Used", Formatters.bytes(gpu.vramUsed))
                        legendRow("VRAM Total", Formatters.bytes(gpu.vramTotal))
                    }
                    Spacer(minLength: 0)
                }
                }
            }
        }
    }

    private func legendRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(loc: label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.metric(11))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
        }
    }
}
