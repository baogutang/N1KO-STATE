import Foundation

struct FanCurvePoint: Codable, Equatable, Identifiable {
    var id: Double { tempC }
    var tempC: Double
    var rpmPercent: Double
}

/// Linear interpolation over sorted temperature anchors.
enum FanCurveInterpolator {
    static let defaultCurve: [FanCurvePoint] = [
        FanCurvePoint(tempC: 50, rpmPercent: 0),
        FanCurvePoint(tempC: 70, rpmPercent: 50),
        FanCurvePoint(tempC: 85, rpmPercent: 100)
    ]

    static func rpmPercent(for tempC: Double, curve: [FanCurvePoint]) -> Double {
        let sorted = curve.sorted { $0.tempC < $1.tempC }
        guard let first = sorted.first, let last = sorted.last else { return 0 }
        if tempC <= first.tempC { return first.rpmPercent }
        if tempC >= last.tempC { return last.rpmPercent }
        for i in 0..<(sorted.count - 1) {
            let a = sorted[i], b = sorted[i + 1]
            guard tempC >= a.tempC, tempC <= b.tempC else { continue }
            let span = b.tempC - a.tempC
            guard span > 0 else { return a.rpmPercent }
            let t = (tempC - a.tempC) / span
            return a.rpmPercent + t * (b.rpmPercent - a.rpmPercent)
        }
        return 0
    }

    static func targetRPM(for fan: FanInfo, percent: Double) -> Int {
        let span = Double(fan.maxRPM - fan.minRPM)
        let rpm = Double(fan.minRPM) + span * min(max(percent, 0), 100) / 100.0
        return Int(rpm.rounded())
    }
}
