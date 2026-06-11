import Foundation
import UserNotifications

/// Evaluates user-configured threshold rules every sampling tick and posts a
/// system notification when a metric crosses its limit.
///
/// Two mechanisms keep notifications from spamming:
/// 1. **Hysteresis** — a rule only re-arms once the metric drops a margin below
///    its threshold, so a value hovering at the limit fires once, not forever.
/// 2. **Cooldown** — even while a condition persists, the same rule won't fire
///    again until `cooldown` has elapsed.
final class AlertManager {

    enum RequiredMetric: String, CaseIterable {
        case cpu, memory, temperature, disk, battery
    }

    private enum Rule: String, CaseIterable {
        case cpu, memory, temperature, disk, battery
    }

    /// Metrics that must keep sampling while alerts are enabled (overrides visibility裁剪).
    var requiredMetrics: Set<RequiredMetric> {
        let s = AppSettings.shared
        guard s.alertsEnabled else { return [] }
        var m = Set<RequiredMetric>()
        if s.cpuAlert { m.insert(.cpu) }
        if s.memAlert { m.insert(.memory) }
        if s.tempAlert { m.insert(.temperature) }
        if s.diskAlert { m.insert(.disk) }
        if s.batteryAlert { m.insert(.battery) }
        return m
    }

    /// Fraction below the threshold a metric must fall to re-arm (0...1 metrics).
    private let hysteresis = 0.05
    /// Degrees below the threshold a temperature must fall to re-arm.
    private let tempHysteresis = 5.0
    /// Minimum gap between repeat notifications for the same rule.
    private let cooldown: TimeInterval = 300

    private var armed: Set<Rule> = Set(Rule.allCases)   // ready to fire
    private var lastFired: [Rule: Date] = [:]
    private var authorized = false
    /// Called once when notification authorization completes (granted or denied).
    var onAuthorizationComplete: (() -> Void)?

    /// `UNUserNotificationCenter.current()` throws an uncatchable Obj-C exception
    /// when the process isn't a real `.app` bundle (e.g. a bare SwiftPM binary):
    /// "bundleProxyForCurrentProcess is nil". Gate every notification call on this.
    static let notificationsSupported: Bool = Bundle.main.bundleURL.pathExtension == "app"

    // MARK: - Authorization

    /// Requests notification permission once, at launch.
    func requestAuthorization() {
        guard Self.notificationsSupported else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
                self?.onAuthorizationComplete?()
            }
        }
    }

    // MARK: - Evaluation

    /// Called every tick with the latest metric snapshot.
    /// - Parameters:
    ///   - cpu: 0...1 total CPU load.
    ///   - mem: 0...1 memory used fraction.
    ///   - tempC: hottest sensor in °C, or nil if unavailable.
    ///   - diskFree: 0...1 free fraction of the primary volume, or nil.
    ///   - battery: 0...1 charge level, or nil if there's no battery.
    ///   - batteryCharging: true when plugged in / charging (suppresses the alert).
    func evaluate(cpu: Double, mem: Double, tempC: Double?, diskFree: Double?,
                  battery: Double? = nil, batteryCharging: Bool = false) {
        let s = AppSettings.shared
        guard s.alertsEnabled else { return }

        if s.cpuAlert {
            check(.cpu, value: cpu, threshold: s.cpuThreshold, margin: hysteresis,
                  title: "High CPU usage", body: "CPU at %@.".locf(Formatters.percent(cpu)))
        }
        if s.memAlert {
            check(.memory, value: mem, threshold: s.memThreshold, margin: hysteresis,
                  title: "High memory usage", body: "Memory at %@.".locf(Formatters.percent(mem)))
        }
        if s.tempAlert, let t = tempC {
            check(.temperature, value: t, threshold: s.tempThreshold, margin: tempHysteresis,
                  title: "High temperature", body: "Sensor peak %@.".locf(Formatters.temperature(t)))
        }
        if s.diskAlert, let free = diskFree {
            // Disk is inverted: fire when *free* drops *below* the threshold.
            checkLow(.disk, value: free, threshold: s.diskFreeThreshold, margin: hysteresis,
                     title: "Low disk space", body: "Only %@ free on the startup disk.".locf(Formatters.percent(free)))
        }
        if s.batteryAlert, let level = battery, !batteryCharging {
            // Only warn while running on battery; charging always re-arms it.
            checkLow(.battery, value: level, threshold: s.batteryThreshold, margin: hysteresis,
                     title: "Low battery", body: "Battery at %@.".locf(Formatters.percent(level)))
        } else if batteryCharging {
            armed.insert(.battery)
        }
    }

    // MARK: - Rule logic

    /// Fires when `value` rises above `threshold`; re-arms below `threshold - margin`.
    private func check(_ rule: Rule, value: Double, threshold: Double, margin: Double,
                       title: String, body: String) {
        if value >= threshold {
            fireIfReady(rule, title: title, body: body)
        } else if value < threshold - margin {
            armed.insert(rule)
        }
    }

    /// Inverted variant: fires when `value` falls below `threshold`.
    private func checkLow(_ rule: Rule, value: Double, threshold: Double, margin: Double,
                          title: String, body: String) {
        if value <= threshold {
            fireIfReady(rule, title: title, body: body)
        } else if value > threshold + margin {
            armed.insert(rule)
        }
    }

    private func fireIfReady(_ rule: Rule, title: String, body: String) {
        guard armed.contains(rule) else { return }
        if let last = lastFired[rule], Date().timeIntervalSince(last) < cooldown { return }
        armed.remove(rule)
        lastFired[rule] = Date()
        post(title: title.loc, body: body)
    }

    private func post(title: String, body: String) {
        guard authorized, Self.notificationsSupported else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
