import SwiftUI

enum ProcessSortMode: String, CaseIterable {
    case cpu, memory
}

struct ProcessListSection: View {
    let cpuList: [ProcSample]
    let memList: [ProcSample]
    let sortMode: ProcessSortMode
    let totalMemory: Double
    let accent: Color
    var onSortToggle: () -> Void
    @State private var killError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onSortToggle) {
                HStack(spacing: 4) {
                    SectionLabel(text: "Top Processes")
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.textTertiary)
                    Text(loc: sortMode == .cpu ? "CPU" : "Memory")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(accent)
                }
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                ForEach(sorted) { p in
                    ProcessRow(name: p.name,
                               value: value(for: p),
                               fraction: fraction(for: p),
                               color: accent,
                               onTerminate: { terminate(p) })
                }
            }
            if let killError {
                Text(killError)
                    .font(.system(size: 9.5))
                    .foregroundColor(Theme.danger)
            }
        }
    }

    private var sorted: [ProcSample] {
        switch sortMode {
        case .cpu: return cpuList
        case .memory: return memList
        }
    }

    private func value(for p: ProcSample) -> String {
        sortMode == .cpu
            ? String(format: "%.1f%%", p.cpu)
            : Formatters.bytes(p.memBytes)
    }

    private func fraction(for p: ProcSample) -> Double {
        sortMode == .cpu ? p.cpu / 100 : (totalMemory > 0 ? p.memBytes / totalMemory : 0)
    }

    private func terminate(_ p: ProcSample) {
        if ProcessMonitor.terminate(pid: p.id) {
            killError = nil
        } else {
            killError = "Could not terminate “%@” — permission denied.".locf(p.name)
        }
    }
}
