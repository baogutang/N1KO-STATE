import SwiftUI

struct MemoryCard: View {
    @ObservedObject var memory: MemoryMonitor
    @ObservedObject var processes: ProcessMonitor
    let snapshot: MonitorDisplaySnapshot
    @ObservedObject private var chartRange = ChartRangeStore.shared
    @State private var processSort: ProcessSortMode = .memory
    @State private var chartValues: [Double] = []
    @State private var lastLongRangeRefresh = Date.distantPast

    private var pressureColor: Color {
        switch snapshot.memoryPressureLevel {
        case .low: return Theme.ok
        case .medium: return Theme.warn
        case .high: return Theme.danger
        }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 11) {
                CardHeader(icon: "memorychip",
                           title: Module.memory.localizedTitle,
                           accent: Theme.memory,
                           trailing: Formatters.percent(snapshot.memoryFraction),
                           trailingColor: pressureColor)

                ChartRangePicker(range: $chartRange.range, accent: Theme.accent)

                MetricChart(values: chartValues,
                            maxValue: 1,
                            color: pressureColor,
                            accessibilityName: "Memory history",
                            accessibilityFormatter: Formatters.percent)
                    .frame(height: 40)
                    .accessibilityLabel("Memory usage chart".loc)

                HStack(spacing: 14) {
                    RingGauge(fraction: snapshot.memoryFraction,
                              color: pressureColor,
                              lineWidth: 9,
                              value: Formatters.bytes(snapshot.memoryUsed),
                              caption: "USED")
                        .frame(width: 78, height: 78)

                    VStack(alignment: .leading, spacing: 7) {
                        legendRow("App", memory.appMemory, Theme.memory)
                        legendRow("Wired", memory.wired, Theme.warn,
                                  help: "Memory that cannot be paged out.")
                        legendRow("Compressed", memory.compressed, Theme.info,
                                  help: "Memory compressed to free physical RAM.")
                        legendRow("Free", snapshot.memoryFree, Theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        SectionLabel(text: "Pressure")
                        Spacer()
                        Text(loc: snapshot.memoryPressureLevel.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(pressureColor)
                    }
                    StackedBar(segments: [
                        .init(fraction: memory.total > 0 ? memory.appMemory / memory.total : 0, color: Theme.memory),
                        .init(fraction: memory.total > 0 ? memory.wired / memory.total : 0, color: Theme.warn),
                        .init(fraction: memory.total > 0 ? memory.compressed / memory.total : 0, color: Theme.info)
                    ], height: 8)
                }

                if memory.swapTotal > 0 {
                    HStack {
                        StatPill(label: "Swap Used", value: Formatters.bytes(memory.swapUsed))
                        Spacer()
                        StatPill(label: "Swap Total", value: Formatters.bytes(memory.swapTotal))
                        Spacer()
                        StatPill(label: "Total RAM", value: Formatters.bytes(memory.total))
                    }
                }

                if !processes.topByCPU.isEmpty || !processes.topByMemory.isEmpty {
                    Divider().overlay(Theme.stroke)
                    ProcessListSection(cpuList: processes.topByCPU,
                                       memList: processes.topByMemory,
                                       sortMode: processSort,
                                       totalMemory: snapshot.memoryTotal,
                                       accent: Theme.memory,
                                       onSortToggle: { processSort = processSort == .cpu ? .memory : .cpu })
                }
            }
        }
        .onAppear { updateChartValues(force: true) }
        .onChange(of: chartRange.range) { _ in updateChartValues(force: true) }
        .onChange(of: memory.history) { _ in updateChartValues() }
    }

    private func legendRow(_ label: String, _ bytes: Double, _ color: Color, help: String? = nil) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(loc: label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .help(help ?? "")
            Spacer(minLength: 6)
            Text(Formatters.bytes(bytes))
                .font(.metric(11))
                .foregroundColor(Theme.textPrimary)
        }
    }

    private func updateChartValues(force: Bool = false) {
        let range = chartRange.resolvedRange
        if !force, range != .m1, Date().timeIntervalSince(lastLongRangeRefresh) < 25 { return }
        chartValues = HistoryStore.shared.values(for: .memory, range: range, shortWindow: memory.history)
        if range != .m1 { lastLongRangeRefresh = Date() }
    }
}
