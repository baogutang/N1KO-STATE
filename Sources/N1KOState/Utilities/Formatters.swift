import Foundation

/// Lightweight, allocation-free metric formatters used across the UI.
enum Formatters {

    /// 0...1 fraction → "12%".
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Bytes → human readable, base-1024 ("1.2 GB").
    static func bytes(_ b: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = max(b, 0)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return String(format: i == 0 ? "%.0f %@" : "%.1f %@", v, units[i])
    }

    /// Bytes/sec → "1.2 MB/s".
    static func rate(_ bytesPerSec: Double) -> String {
        bytes(bytesPerSec) + "/s"
    }

    /// Compact rate for the tight menu bar: "1.2M" (no unit suffix).
    static func rateCompact(_ bytesPerSec: Double) -> String {
        let units = ["B", "K", "M", "G"]
        var v = max(bytesPerSec, 0)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        if i == 0 { return String(format: "%.0f%@", v, units[i]) }
        return String(format: v >= 100 ? "%.0f%@" : "%.1f%@", v, units[i])
    }

    /// Seconds → "3d 4h" / "4h 12m" / "12m".
    static func uptime(_ seconds: TimeInterval) -> String {
        let t = Int(max(seconds, 0))
        let d = t / 86400
        let h = (t % 86400) / 3600
        let m = (t % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    /// "45°" (or "113°F" when the Fahrenheit preference is on).
    static func temperature(_ celsius: Double) -> String {
        if AppSettings.shared.useFahrenheit {
            return "\(Int((celsius * 9 / 5 + 32).rounded()))°F"
        }
        return "\(Int(celsius.rounded()))°"
    }
}
