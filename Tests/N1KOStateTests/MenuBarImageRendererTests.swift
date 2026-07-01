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

    func testAdaptiveColorModeUsesTemplateImage() {
        var colorful = input(layout: .standard, showNetwork: false)
        colorful.colorMode = .colorful
        var adaptive = input(layout: .standard, showNetwork: false)
        adaptive.colorMode = .adaptive

        XCTAssertFalse(MenuBarImageRenderer.render(colorful).isTemplate)
        XCTAssertTrue(MenuBarImageRenderer.render(adaptive).isTemplate)
    }

    func testMetricValueChangesDoNotChangeRenderedWidth() {
        for layout in MenuBarLayout.allCases {
            var low = input(layout: layout, showNetwork: false)
            low.cpu = 0.07
            low.gpu = 0.13
            low.mem = 0.85
            low.battery = 0.09

            var high = input(layout: layout, showNetwork: false)
            high.cpu = 1.0
            high.gpu = 1.0
            high.mem = 1.0
            high.battery = 1.0

            XCTAssertEqual(MenuBarImageRenderer.render(low).size.width,
                           MenuBarImageRenderer.render(high).size.width,
                           "Expected \(layout.rawValue) width to be stable across digit changes")
        }
    }

    func testNetworkRateChangesDoNotChangeRenderedWidth() {
        for layout in MenuBarLayout.allCases {
            var low = input(layout: layout, showNetwork: true)
            low.down = 0
            low.up = 0

            var high = input(layout: layout, showNetwork: true)
            high.down = 988_800_000
            high.up = 888_800_000

            XCTAssertEqual(MenuBarImageRenderer.render(low).size.width,
                           MenuBarImageRenderer.render(high).size.width,
                           "Expected \(layout.rawValue) network width to be stable across rate changes")
        }
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
