import Foundation

/// Weak bridge so `AppSettings` can disable curve without a direct `MonitorHub` reference.
enum FanCurveController {
    static weak var shared: FanControlService?
}
