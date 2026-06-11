import SwiftUI

struct NetworkCard: View {
    @ObservedObject var network: NetworkMonitor
    @ObservedObject var settings = AppSettings.shared

    private let downColor = Theme.info
    private let upColor = Color(hex: 0x32D74B)

    private var downChart: [Double] {
        let range = HistoryStore.Range(rawValue: settings.chartTimeRange) ?? .m1
        return HistoryStore.shared.values(for: .netDown, range: range, shortWindow: network.downHistory)
    }

    private var upChart: [Double] {
        let range = HistoryStore.Range(rawValue: settings.chartTimeRange) ?? .m1
        return HistoryStore.shared.values(for: .netUp, range: range, shortWindow: network.upHistory)
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                CardHeader(icon: "network",
                           title: Module.network.localizedTitle,
                           accent: Theme.ok,
                           trailing: network.isConnected ? (network.primaryInterface ?? "—") : "Offline".loc,
                           trailingColor: network.isConnected ? Theme.textSecondary : Theme.danger)

                ChartRangePicker(range: $settings.chartTimeRange, accent: settings.accent)

                HStack(spacing: 12) {
                    rateBlock(symbol: "arrow.down", label: "Download",
                              rate: network.downloadRate, color: downColor)
                    rateBlock(symbol: "arrow.up", label: "Upload",
                              rate: network.uploadRate, color: upColor)
                }

                ZStack {
                    MetricChart(values: downChart, maxValue: nil, color: downColor)
                    MetricChart(values: upChart, maxValue: nil, color: upColor, fill: false)
                }
                .frame(height: 50)
                .accessibilityLabel("Network throughput chart".loc)

                Divider().overlay(Theme.stroke)

                HStack {
                    StatPill(label: "Local IP", value: network.localIP ?? "—")
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(network.isConnected ? Theme.ok : Theme.danger)
                            .frame(width: 7, height: 7)
                        Text(loc: network.isConnected ? "Connected" : "Disconnected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private func rateBlock(symbol: String, label: String, rate: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(color)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(color.opacity(0.15))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text(label.loc.uppercased())
                    .font(.system(size: 9, weight: .semibold))
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
