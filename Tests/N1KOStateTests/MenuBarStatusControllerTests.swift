import AppKit
import XCTest
@testable import N1KOState

final class MenuBarStatusControllerTests: XCTestCase {

    func testStatusControllerDoesNotInstallHoverPreviewSelectors() {
        let controller = MenuBarStatusController(hub: MonitorHub())
        defer { NSStatusBar.system.removeStatusItem(controller.statusItem) }

        XCTAssertFalse(controller.responds(to: NSSelectorFromString("mouseEntered:")))
        XCTAssertFalse(controller.responds(to: NSSelectorFromString("mouseExited:")))
    }
}
