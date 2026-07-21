import SwiftUI

struct DiskCard: View {
    @ObservedObject var disk: DiskMonitor
    let snapshot: MonitorDisplaySnapshot

    private let accent = Color(hex: 0x64D2FF)        // cyan
    private let readColor = Color(hex: 0x5E5CE6)     // indigo
    private let writeColor = Color(hex: 0xFF9F0A)    // orange

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                CardHeader(icon: "internaldrive",
                           title: "Disk",
                           accent: accent,
                           trailing: snapshot.diskPrimaryFree.map { "%@ free".locf(Formatters.bytes($0)) })

                if !disk.volumes.isEmpty {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(disk.volumes.prefix(3)) { v in
                            VStack(spacing: 5) {
                                RingGauge(fraction: v.fraction,
                                          color: Theme.semantic(for: v.fraction),
                                          lineWidth: 7,
                                          value: Formatters.percent(v.fraction))
                                    .frame(width: 58, height: 58)
                                Text(v.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(Theme.textSecondary)
                                    .lineLimit(1)
                                Text(Formatters.bytes(v.total))
                                    .font(Theme.TypeScale.caption)
                                    .foregroundColor(Theme.textTertiary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        if disk.volumes.count < 3 { Spacer(minLength: 0) }
                    }
                }

                Divider().overlay(Theme.stroke)

                HStack(spacing: 12) {
                    ioBlock(symbol: "arrow.down.circle.fill", label: "Read",
                            rate: snapshot.diskReadRate, color: readColor)
                    ioBlock(symbol: "arrow.up.circle.fill", label: "Write",
                            rate: snapshot.diskWriteRate, color: writeColor)
                }

                ZStack {
                    MetricChart(values: disk.readHistory,
                                maxValue: nil,
                                color: readColor,
                                accessibilityName: "Disk read history",
                                accessibilityFormatter: Formatters.rateCompact)
                    MetricChart(values: disk.writeHistory,
                                maxValue: nil,
                                color: writeColor,
                                fill: false,
                                accessibilityName: "Disk write history",
                                accessibilityFormatter: Formatters.rateCompact)
                }
                .frame(height: 44)
            }
        }
    }

    private func ioBlock(symbol: String, label: String, rate: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.loc.uppercased())
                    .font(Theme.TypeScale.caption.weight(.semibold))
                    .foregroundColor(Theme.textTertiary)
                Text(Formatters.rate(rate))
                    .font(.metric(13, weight: .bold))
                    .foregroundColor(Theme.textPrimary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
