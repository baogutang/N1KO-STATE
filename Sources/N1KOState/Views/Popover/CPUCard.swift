import SwiftUI

struct CPUCard: View {
    @ObservedObject var cpu: CPUMonitor
    @ObservedObject var memory: MemoryMonitor
    @ObservedObject var processes: ProcessMonitor
    let snapshot: MonitorDisplaySnapshot
    @ObservedObject private var chartRange = ChartRangeStore.shared
    @State private var processSort: ProcessSortMode = .cpu
    @State private var chartValues: [Double] = []
    @State private var lastLongRangeRefresh = Date.distantPast

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                CardHeader(icon: "cpu",
                           title: Module.cpu.localizedTitle,
                           accent: Theme.info,
                           trailing: Formatters.percent(snapshot.cpuUsage),
                           trailingColor: Theme.semantic(for: snapshot.cpuUsage))

                ChartRangePicker(range: $chartRange.range, accent: Theme.accent)

                MetricChart(values: chartValues,
                            maxValue: 1,
                            color: Theme.semantic(for: snapshot.cpuUsage),
                            accessibilityName: "CPU usage history",
                            accessibilityFormatter: Formatters.percent)
                    .frame(height: 52)

                if !cpu.cores.isEmpty {
                    CoreGrid(cores: cpu.cores)
                }

                HStack(spacing: 0) {
                    StatPill(label: "Load 1m", value: String(format: "%.2f", snapshot.cpuLoadAverageOne),
                             help: "Average runnable threads over the last minute.")
                    Spacer()
                    StatPill(label: "Load 5m", value: String(format: "%.2f", cpu.loadAverage.five),
                             help: "Average runnable threads over the last five minutes.")
                    Spacer()
                    StatPill(label: "Uptime", value: Formatters.uptime(snapshot.cpuUptime))
                    if let f = cpu.frequency {
                        Spacer()
                        StatPill(label: "Freq", value: String(format: "%.1fG", f))
                    }
                }

                if !processes.topByCPU.isEmpty || !processes.topByMemory.isEmpty {
                    Divider().overlay(Theme.stroke)
                    ProcessListSection(cpuList: processes.topByCPU,
                                       memList: processes.topByMemory,
                                       sortMode: processSort,
                                       totalMemory: memory.total,
                                       accent: Theme.info,
                                       onSortToggle: { processSort = processSort == .cpu ? .memory : .cpu })
                }
            }
        }
        .onAppear { updateChartValues(force: true) }
        .onChange(of: chartRange.range) { _ in updateChartValues(force: true) }
        .onChange(of: cpu.history) { _ in updateChartValues() }
    }

    private func updateChartValues(force: Bool = false) {
        let range = chartRange.resolvedRange
        if !force, range != .m1, Date().timeIntervalSince(lastLongRangeRefresh) < 25 { return }
        chartValues = HistoryStore.shared.values(for: .cpu, range: range, shortWindow: cpu.history)
        if range != .m1 { lastLongRangeRefresh = Date() }
    }
}
