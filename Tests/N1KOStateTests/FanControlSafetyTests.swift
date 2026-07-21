import XCTest
@testable import N1KOState

final class FanControlSafetyTests: XCTestCase {
    func testManualModeCanReturnToAutomaticBeforeAWriteIsApplied() {
        let service = FanControlService()
        service.enableManual(fanId: 0, rpm: 2_500)

        XCTAssertEqual(service.mode, .manual)
        XCTAssertEqual(service.manualFanIDs, [0])
        XCTAssertEqual(service.manualTargets[0], 2_500)

        service.disableManual(fanId: 0)
        XCTAssertEqual(service.mode, .auto)
        XCTAssertTrue(service.manualFanIDs.isEmpty)
        XCTAssertTrue(service.appliedFanIDs.isEmpty)
    }

    func testCurveInterpolationAndModeBoundsTargets() {
        let service = FanControlService()
        service.enableCurveMode()
        XCTAssertEqual(service.mode, .curve)

        let fan = FanInfo(id: 0, name: "Fixture", rpm: 2_000, targetRPM: 2_000,
                          minRPM: 1_000, maxRPM: 5_000, forced: false)
        XCTAssertEqual(FanCurveInterpolator.targetRPM(for: fan, percent: -10), 1_000)
        XCTAssertEqual(FanCurveInterpolator.targetRPM(for: fan, percent: 50), 3_000)
        XCTAssertEqual(FanCurveInterpolator.targetRPM(for: fan, percent: 120), 5_000)
        XCTAssertEqual(FanCurveInterpolator.rpmPercent(for: 60,
                                                       curve: FanCurveInterpolator.defaultCurve),
                       25, accuracy: 0.0001)

        service.resetAllFans()
        XCTAssertEqual(service.mode, .auto)
    }

    func testThermalSafetyCancelsPendingManualIntentAtThreshold() {
        let service = FanControlService()
        service.enableManual(fanId: 0, rpm: 3_000)

        service.enforceThermalSafety(peakCelsius: 94.9)
        XCTAssertEqual(service.mode, .manual)

        service.enforceThermalSafety(peakCelsius: 95)
        XCTAssertEqual(service.mode, .auto)
        XCTAssertTrue(service.manualFanIDs.isEmpty)
        XCTAssertNotNil(service.lastError)
    }
}
