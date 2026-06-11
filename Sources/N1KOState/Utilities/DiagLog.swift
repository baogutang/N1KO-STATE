import Foundation
import os

/// Launch-time diagnostic log mirrored to disk for remote troubleshooting.
enum DiagLog {
    private static let subsystem = "com.n1ko.state.monitor"
    private static let logDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/N1KO-STATE", isDirectory: true)
    }()
    private static let logFile = logDir.appendingPathComponent("launch.log")
    private static let lock = NSLock()
    private static var bootstrapped = false

    static var logDirectoryURL: URL { logDir }

    /// Serial queue: file I/O never blocks the caller and needs no locking.
    private static let ioQueue = DispatchQueue(label: "com.n1ko.state.monitor.diaglog", qos: .utility)

    private static let tsFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func bootstrap() {
        lock.lock()
        let first = !bootstrapped
        bootstrapped = true
        lock.unlock()
        guard first else { return }
        let osVer = ProcessInfo.processInfo.operatingSystemVersionString
        let arch = currentArch()
        let model = hwModel()
        ioQueue.async {
            try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        }
        log("bootstrap", "N1KO-STATE launch — macOS \(osVer), model \(model), arch \(arch)")
    }

    static func log(_ category: String, _ message: String) {
        bootstrap()
        Logger(subsystem: subsystem, category: category).info("\(message, privacy: .public)")
        let when = Date()
        ioQueue.async {
            let line = tsFormatter.string(from: when) + " [\(category)] " + message + "\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: logFile, options: .atomic)
            }
        }
    }

    private static func currentArch() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func hwModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buf, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buf)
    }
}
