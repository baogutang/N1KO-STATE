import SwiftUI

struct NetworkCard: View {
    @ObservedObject var network: NetworkMonitor
    let snapshot: MonitorDisplaySnapshot
    @ObservedObject private var chartRange = ChartRangeStore.shared
    @State private var downChart: [Double] = []
    @State private var upChart: [Double] = []
    @State private var lastLongRangeRefresh = Date.distantPast

    private let downColor = Theme.info
    private let upColor = Color(hex: 0x32D74B)

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                CardHeader(icon: "network",
                           title: Module.network.localizedTitle,
                           accent: Theme.ok,
                           trailing: snapshot.networkIsConnected ? (network.primaryInterface ?? "—") : "Offline".loc,
                           trailingColor: snapshot.networkIsConnected ? Theme.textSecondary : Theme.danger)

                ChartRangePicker(range: $chartRange.range, accent: Theme.accent)

                HStack(spacing: 12) {
                    rateBlock(symbol: "arrow.down", label: "Download",
                              rate: snapshot.networkDownloadRate, color: downColor)
                    rateBlock(symbol: "arrow.up", label: "Upload",
                              rate: snapshot.networkUploadRate, color: upColor)
                }

                ZStack {
                    MetricChart(values: downChart,
                                maxValue: nil,
                                color: downColor,
                                accessibilityName: "Download history",
                                accessibilityFormatter: Formatters.rateCompact)
                    MetricChart(values: upChart,
                                maxValue: nil,
                                color: upColor,
                                fill: false,
                                accessibilityName: "Upload history",
                                accessibilityFormatter: Formatters.rateCompact)
                }
                .frame(height: 50)

                Divider().overlay(Theme.stroke)

                HStack {
                    StatPill(label: "Local IP", value: snapshot.networkLocalIP ?? "—")
                    Spacer()
                    HStack(spacing: 5) {
                        Circle()
                            .fill(snapshot.networkIsConnected ? Theme.ok : Theme.danger)
                            .frame(width: 7, height: 7)
                        Text(loc: snapshot.networkIsConnected ? "Connected" : "Disconnected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }
        }
        .onAppear { updateChartValues(force: true) }
        .onChange(of: chartRange.range) { _ in updateChartValues(force: true) }
        .onChange(of: network.downHistory) { _ in updateChartValues() }
        .onChange(of: network.upHistory) { _ in updateChartValues() }
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

    private func updateChartValues(force: Bool = false) {
        let range = chartRange.resolvedRange
        if !force, range != .m1, Date().timeIntervalSince(lastLongRangeRefresh) < 25 { return }
        downChart = HistoryStore.shared.values(for: .netDown, range: range, shortWindow: network.downHistory)
        upChart = HistoryStore.shared.values(for: .netUp, range: range, shortWindow: network.upHistory)
        if range != .m1 { lastLongRangeRefresh = Date() }
    }
}
