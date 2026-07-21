import AppKit
import SwiftUI
import XCTest
@testable import N1KOState

@MainActor
final class WP2NativeFoundationTests: XCTestCase {
    func testSettingsRouterRestoresDestinationAndFindsControls() {
        let suiteName = "N1KOStateTests.settings-navigation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let navigation = SettingsNavigationModel(selectedTab: .menuBar, defaults: defaults)
        XCTAssertEqual(defaults.string(forKey: SettingsNavigationModel.lastDestinationKey),
                       SettingsTab.menuBar.rawValue)

        let result = try! XCTUnwrap(SettingsSearchIndex.search("fan curve").first)
        navigation.navigate(to: result)
        XCTAssertEqual(navigation.selectedTab, .sensors)
        XCTAssertEqual(navigation.pendingControlID, .fanCurve)

        let restored = SettingsNavigationModel(defaults: defaults)
        XCTAssertEqual(restored.selectedTab, .sensors)
        XCTAssertTrue(SettingsSearchIndex.search("definitely missing").isEmpty)
        XCTAssertEqual(Set(SettingsSearchIndex.items.map(\.control)),
                       Set(SettingsControlID.allCases))
    }

    func testSettingsUsesOnePersistentNativeWindow() {
        let controller = SettingsWindowController()
        let first = controller.prepareWindowForTesting()

        for _ in 0..<100 {
            XCTAssertEqual(controller.prepareWindowForTesting(), first)
        }

        XCTAssertEqual(controller.windowCreationCount, 1)
        XCTAssertEqual(controller.windowIdentity, first)
        XCTAssertEqual(SettingsLayoutPolicy.minimumSize, NSSize(width: 900, height: 600))

        let hub = MonitorHub()
        controller.show(fans: hub.fans, hub: hub, tab: .overview)
        let hostingIdentity = controller.hostingIdentity
        XCTAssertEqual(controller.windowIdentity, first)
        controller.closeForPerformanceBenchmark()
        controller.showAbout(fans: hub.fans, hub: hub)
        XCTAssertEqual(controller.windowIdentity, first)
        XCTAssertEqual(controller.hostingIdentity, hostingIdentity)
        controller.closeForPerformanceBenchmark()
    }

    func testEnglishSimplifiedAndTraditionalSettingsRenderAtMinimumWindow() throws {
        let originalBundle = LocalizationManager.shared.bundle
        defer { LocalizationManager.shared.useBundleForTesting(originalBundle) }

        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let hub = MonitorHub()

        for language in ["en", "zh-Hans", "zh-Hant"] {
            let path = repositoryRoot
                .appendingPathComponent("Localization")
                .appendingPathComponent("\(language).lproj")
                .path
            let bundle = try XCTUnwrap(Bundle(path: path))
            LocalizationManager.shared.useBundleForTesting(bundle)

            let view = SettingsView(
                fans: hub.fans,
                hub: hub,
                initialTab: .overview,
                navigation: SettingsNavigationModel(selectedTab: .overview)
            )
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: SettingsLayoutPolicy.minimumSize)
            hosting.layoutSubtreeIfNeeded()

            XCTAssertEqual(hosting.frame.size, SettingsLayoutPolicy.minimumSize, language)
            XCTAssertTrue(hosting.frame.width.isFinite, language)
            XCTAssertTrue(hosting.frame.height.isFinite, language)
        }
    }

    func testPreferenceDomainsShareTheSingleSettingsAuthority() {
        let preferences = AppPreferences(root: .shared)
        let identity = ObjectIdentifier(preferences.root)

        XCTAssertEqual(preferences.general.rootIdentity, identity)
        XCTAssertEqual(preferences.monitoring.rootIdentity, identity)
        XCTAssertEqual(preferences.menuBar.rootIdentity, identity)
        XCTAssertEqual(preferences.quickPanel.rootIdentity, identity)
        XCTAssertEqual(preferences.safety.rootIdentity, identity)
        XCTAssertEqual(preferences.agent.rootIdentity, identity)
    }

    func testQuickPanelRowsHaveDeterministicGeometryAndSingleDisclosure() {
        let expected = QuickPanelLayoutMetrics.collapsedBodyHeight(moduleCount: 7, maximum: 900)
        for _ in 0..<100 {
            XCTAssertEqual(QuickPanelLayoutMetrics.collapsedBodyHeight(moduleCount: 7, maximum: 900),
                           expected)
        }

        var disclosure = QuickPanelDisclosureState()
        disclosure.toggle(.cpu)
        XCTAssertEqual(disclosure.expandedModule, .cpu)
        disclosure.toggle(.memory)
        XCTAssertEqual(disclosure.expandedModule, .memory)
        disclosure.toggle(.memory)
        XCTAssertNil(disclosure.expandedModule)
    }

    func testSettingsPreviewProjectionContainsNoActions() {
        var snapshot = MonitorDisplaySnapshot()
        snapshot.cpuUsage = 0.42
        snapshot.memoryUsed = 8
        snapshot.memoryTotal = 16
        snapshot.sensorPeakCelsius = 72

        let preview = QuickPanelPreviewModel.make(snapshot: snapshot,
                                                  modules: [.cpu, .memory, .sensors])
        XCTAssertEqual(preview.modules.map(\.module), [.cpu, .memory, .sensors])
        XCTAssertFalse(containsFunction(preview))
    }

    func testChartAccessibilityReportsCurrentRangeAndTrend() throws {
        let rising = try XCTUnwrap(ChartAccessibilitySummary(values: [0.2, 0.4, 0.8]))
        XCTAssertEqual(rising.current, 0.8)
        XCTAssertEqual(rising.minimum, 0.2)
        XCTAssertEqual(rising.maximum, 0.8)
        XCTAssertEqual(rising.trend, .rising)

        let steady = try XCTUnwrap(ChartAccessibilitySummary(values: [0.5, 0.502, 0.501]))
        XCTAssertEqual(steady.trend, .steady)
        XCTAssertNil(ChartAccessibilitySummary(values: []))
    }

    func testContentTypeAndMotionTokensMeetWP2Bounds() {
        XCTAssertGreaterThanOrEqual(Theme.TypeScale.minimumContentPointSize, 10)
        XCTAssertEqual(Theme.TypeScale.standardBodyPointSize, 13)
        XCTAssertLessThanOrEqual(Theme.Motion.feedback, 0.12)
        XCTAssertGreaterThanOrEqual(Theme.Motion.disclosure, 0.18)
        XCTAssertLessThanOrEqual(Theme.Motion.disclosure, 0.25)
    }

    private func containsFunction(_ value: Any) -> Bool {
        if String(describing: type(of: value)).contains("->") { return true }
        let mirror = Mirror(reflecting: value)
        return mirror.children.contains { containsFunction($0.value) }
    }
}
