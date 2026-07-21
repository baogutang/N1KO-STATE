import XCTest
@testable import N1KOState

@MainActor
final class PresentationCoordinatorTests: XCTestCase {
    func testQuickPanelHostIdentitySurvivesOneHundredCloseCycles() {
        let hub = MonitorHub()
        let menuBar = MenuBarStatusController(hub: hub)
        let coordinator = PresentationCoordinator(hub: hub, menuBar: menuBar)

        coordinator.prepareQuickPanelHost()
        let first = coordinator.quickPanelHostIdentity
        for _ in 0..<100 {
            coordinator.closeQuickPanel()
            coordinator.prepareQuickPanelHost()
            XCTAssertEqual(coordinator.quickPanelHostIdentity, first)
        }

        XCTAssertNotNil(first)
        XCTAssertFalse(coordinator.isQuickPanelVisible)
    }

    func testPinnedIslandSettingsActionOpensAgentCenterOnFreshController() {
        let hub = MonitorHub()
        let menuBar = MenuBarStatusController(hub: hub)
        let settingsController = SettingsWindowController()
        _ = PresentationCoordinator(
            hub: hub,
            menuBar: menuBar,
            settingsController: settingsController
        )

        settingsController.present()

        XCTAssertTrue(settingsController.isVisibleForPerformanceBenchmark)
        XCTAssertEqual(settingsController.selectedTabForTesting, .agentCenter)
        settingsController.closeForPerformanceBenchmark()
    }
}
