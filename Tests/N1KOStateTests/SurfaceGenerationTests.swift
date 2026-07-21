import XCTest
@testable import N1KOState

final class SurfaceGenerationTests: XCTestCase {
    func testMenuBarInputMatchesQuickPanelDisplaySnapshotExactly() {
        let panelSnapshot = MonitorDisplaySnapshot(
            generationID: 42,
            sampledAtUptimeNanoseconds: 123,
            cpuUsage: 0.31,
            gpuUtilization: 0.27,
            memoryUsed: 12,
            memoryFree: 4,
            memoryTotal: 16,
            networkDownloadRate: 12_345,
            networkUploadRate: 6_789,
            batteryIsPresent: true,
            batteryPercentage: 0.84,
            batteryIsCharging: true
        )
        let metrics = MenuBarStatusController.EffectiveMenuMetrics(
            showCPU: true,
            showGPU: true,
            showMemory: true,
            showBattery: true,
            showNetwork: true,
            order: MenuBarMetric.allCases
        )

        let menuInput = MenuBarStatusController.makeRenderInput(
            snapshot: panelSnapshot,
            effective: metrics,
            layout: .standard,
            compact: false,
            fontStyle: .rounded,
            colorMode: .colorful,
            fontSize: 11
        )

        XCTAssertEqual(menuInput.generationID, panelSnapshot.generationID)
        XCTAssertEqual(menuInput.cpu, panelSnapshot.cpuUsage)
        XCTAssertEqual(menuInput.gpu, panelSnapshot.gpuUtilization)
        XCTAssertEqual(menuInput.mem, panelSnapshot.memoryFraction)
        XCTAssertEqual(menuInput.battery, panelSnapshot.batteryPercentage)
        XCTAssertEqual(menuInput.batteryCharging, panelSnapshot.batteryIsCharging)
        XCTAssertEqual(menuInput.down, panelSnapshot.networkDownloadRate)
        XCTAssertEqual(menuInput.up, panelSnapshot.networkUploadRate)
    }
}
