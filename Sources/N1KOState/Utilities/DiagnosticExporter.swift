import Foundation
import AppKit

enum DiagnosticExporter {
    enum ExportError: Error {
        case message(String)
    }

    /// Export launch.log + monitor snapshot + system info as a zip on the Desktop.
    static func export(hub: MonitorHub) -> Result<URL, ExportError> {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("n1ko-diag-\(stamp)", isDirectory: true)
        let zipPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/N1KO-STATE-diagnostic-\(stamp).zip")

        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: work) }

            let logSrc = DiagLog.logDirectoryURL.appendingPathComponent("launch.log")
            if FileManager.default.fileExists(atPath: logSrc.path) {
                try FileManager.default.copyItem(at: logSrc, to: work.appendingPathComponent("launch.log"))
            }

            let snapshot = buildSnapshot(hub: hub)
            try snapshot.write(to: work.appendingPathComponent("snapshot.json"), atomically: true, encoding: .utf8)

            let sys = buildSystemInfo()
            try sys.write(to: work.appendingPathComponent("system.txt"), atomically: true, encoding: .utf8)

            if FileManager.default.fileExists(atPath: zipPath.path) {
                try FileManager.default.removeItem(at: zipPath)
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            proc.arguments = ["-r", zipPath.path, "."]
            proc.currentDirectoryURL = work
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0 else {
                return .failure(.message("zip failed (exit \(proc.terminationStatus))"))
            }
            return .success(zipPath)
        } catch {
            return .failure(.message(error.localizedDescription))
        }
    }

    private static func buildSystemInfo() -> String {
        var lines: [String] = []
        lines.append("N1KO-STATE \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
        lines.append(ProcessInfo.processInfo.operatingSystemVersionString)
        lines.append("arch: \(ProcessInfo.processInfo.machineArchitecture)")
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        if size > 0 {
            var buf = [CChar](repeating: 0, count: size)
            if sysctlbyname("hw.model", &buf, &size, nil, 0) == 0 {
                lines.append("model: \(String(cString: buf))")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func buildSnapshot(hub: MonitorHub) -> String {
        let memFrac = hub.memory.total > 0 ? hub.memory.used / hub.memory.total : 0
        let payload: [String: Any] = [
            "cpuUsage": hub.cpu.totalUsage,
            "memoryFraction": memFrac,
            "gpuUtil": hub.gpu.utilization,
            "networkDown": hub.network.downloadRate,
            "networkUp": hub.network.uploadRate,
            "peakTempC": hub.sensors.peakCelsius as Any,
            "batteryPercent": hub.battery.isPresent ? hub.battery.percentage as Any : NSNull(),
            "fanCount": hub.fans.fans.count,
            "helperState": String(describing: hub.fans.helperState),
            "history": HistoryStore.shared.snapshot()
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}

private extension ProcessInfo {
    var machineArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}
