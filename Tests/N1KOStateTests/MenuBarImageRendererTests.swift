import AppKit
import XCTest
@testable import N1KOState

final class MenuBarImageRendererTests: XCTestCase {

    func testStackedLayoutIsNarrowerThanStandardForCommonMetrics() {
        let standard = MenuBarImageRenderer.render(input(layout: .standard, showNetwork: false))
        let stacked = MenuBarImageRenderer.render(input(layout: .stacked, showNetwork: false))

        XCTAssertEqual(standard.size.height, 22)
        XCTAssertEqual(stacked.size.height, 22)
        XCTAssertLessThan(stacked.size.width, standard.size.width)
    }

    func testAllLayoutsRenderNonEmptyImages() {
        for layout in MenuBarLayout.allCases {
            let image = MenuBarImageRenderer.render(input(layout: layout))
            XCTAssertGreaterThan(image.size.width, 20, "Expected \(layout.rawValue) to render a visible image")
            XCTAssertEqual(image.size.height, 22)
            XCTAssertFalse(image.accessibilityDescription?.isEmpty ?? true)
        }
    }

    func testMinimalLayoutKeepsMetricsCompact() {
        let standard = MenuBarImageRenderer.render(input(layout: .standard))
        let minimal = MenuBarImageRenderer.render(input(layout: .minimal))

        XCTAssertLessThan(minimal.size.width, standard.size.width)
    }

    func testFontSizeAffectsRenderedWidth() {
        var small = input(layout: .standard, showNetwork: false)
        small.fontSize = 9
        var large = input(layout: .standard, showNetwork: false)
        large.fontSize = 13

        let smallImage = MenuBarImageRenderer.render(small)
        let largeImage = MenuBarImageRenderer.render(large)

        XCTAssertGreaterThan(largeImage.size.width, smallImage.size.width)
    }

    private func input(layout: MenuBarLayout, showNetwork: Bool = true) -> MenuBarImageRenderer.Input {
        MenuBarImageRenderer.Input(
            cpu: 0.42,
            gpu: 0.18,
            mem: 0.63,
            battery: 0.86,
            batteryCharging: false,
            down: 1_250_000,
            up: 280_000,
            showCPU: true,
            showGPU: true,
            showMem: true,
            showBattery: true,
            showNet: showNetwork,
            metricOrder: MenuBarMetric.allCases,
            height: 22,
            layout: layout,
            compact: false,
            fontStyle: .rounded,
            fontSize: 11
        )
    }
}
