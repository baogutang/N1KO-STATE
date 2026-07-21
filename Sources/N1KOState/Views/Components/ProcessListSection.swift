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
    @State private var pendingTermination: ProcSample?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onSortToggle) {
                HStack(spacing: 4) {
                    SectionLabel(text: "Top Processes")
                    Image(systemName: "arrow.up.arrow.down")
                        .font(Theme.TypeScale.caption.weight(.bold))
                        .foregroundColor(Theme.textTertiary)
                    Text(loc: sortMode == .cpu ? "CPU" : "Memory")
                        .font(Theme.TypeScale.caption.weight(.semibold))
                        .foregroundColor(accent)
                }
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                ForEach(sorted, id: \.id) { p in
                    ProcessRow(name: p.name,
                               value: value(for: p),
                               fraction: fraction(for: p),
                               color: accent,
                               onTerminate: { pendingTermination = p })
                }
            }
            if let killError {
                Text(killError)
                    .font(Theme.TypeScale.caption)
                    .foregroundColor(Theme.danger)
            }
        }
        .alert(terminationTitle, isPresented: terminationAlertIsPresented) {
            Button("Cancel".loc, role: .cancel) {
                pendingTermination = nil
            }
            Button("Terminate Process".loc, role: .destructive) {
                guard let process = pendingTermination else { return }
                pendingTermination = nil
                terminate(process)
            }
        } message: {
            if let process = pendingTermination {
                Text("Terminate “%@” (PID %d)? Unsaved work in this process may be lost."
                    .locf(process.name, process.id))
            }
        }
    }

    private var terminationAlertIsPresented: Binding<Bool> {
        Binding(
            get: { pendingTermination != nil },
            set: { if !$0 { pendingTermination = nil } }
        )
    }

    private var terminationTitle: String {
        guard let process = pendingTermination else { return "Terminate Process".loc }
        return "Terminate “%@”?".locf(process.name)
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
