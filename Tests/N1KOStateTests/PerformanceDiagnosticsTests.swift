import XCTest
@testable import N1KOState

final class PerformanceDiagnosticsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PerformanceDiagnostics.reset()
    }

    func testEventAndIntervalCountersAreExportable() {
        PerformanceDiagnostics.event(.quickPanelUpdate)
        PerformanceDiagnostics.measure(.snapshotCommit) {
            _ = (0..<100).reduce(0, +)
        }

        let snapshot = PerformanceDiagnostics.snapshot()
        XCTAssertEqual(snapshot.counters[PerformanceMetric.quickPanelUpdate.rawValue]?.count, 1)
        XCTAssertEqual(snapshot.counters[PerformanceMetric.snapshotCommit.rawValue]?.count, 1)
        XCTAssertNotNil(snapshot.jsonObject["counters"])
    }

    func testResetClearsAllCounters() {
        PerformanceDiagnostics.event(.menuBarRender)
        PerformanceDiagnostics.reset()
        XCTAssertTrue(PerformanceDiagnostics.snapshot().counters.isEmpty)
    }
}
