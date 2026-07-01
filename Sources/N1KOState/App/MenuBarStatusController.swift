import AppKit
import Combine

/// Drives the menu-bar `NSStatusItem` image from live monitor readings.
///
/// Uses a fixed-length `NSStatusItem` + `NSImage` rendering (not SwiftUI
/// `MenuBarExtra`) because the latter is unreliable on macOS Tahoe.
final class MenuBarStatusController: NSObject {

    let statusItem: NSStatusItem
    private let hub: MonitorHub
    private var cancellables = Set<AnyCancellable>()

    var onClick: (() -> Void)?

    private static let barHeight: CGFloat = 22
    private var lastRenderSignature: String?
    private var redrawScheduled = false

    init(hub: MonitorHub) {
        self.hub = hub
        statusItem = NSStatusBar.system.statusItem(withLength: 184)
        super.init()
    }

    func install() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = nil

        redraw(force: true)
        bindRedraws()
    }

    private func bindRedraws() {
        hub.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scheduleRedraw() }
            .store(in: &cancellables)

        let s = AppSettings.shared
        let settingsPub = [
            s.$menuCPU.map { _ in () }.eraseToAnyPublisher(),
            s.$menuGPU.map { _ in () }.eraseToAnyPublisher(),
            s.$menuMemory.map { _ in () }.eraseToAnyPublisher(),
            s.$menuBattery.map { _ in () }.eraseToAnyPublisher(),
            s.$menuNetwork.map { _ in () }.eraseToAnyPublisher(),
            s.$menuCompact.map { _ in () }.eraseToAnyPublisher(),
            s.$menuBarLayout.map { _ in () }.eraseToAnyPublisher(),
            s.$menuBarOrder.map { _ in () }.eraseToAnyPublisher(),
            s.$menuBarFontStyle.map { _ in () }.eraseToAnyPublisher(),
            s.$menuBarColorMode.map { _ in () }.eraseToAnyPublisher(),
            s.$menuBarFontSize.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(settingsPub)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.redrawNow() }
            .store(in: &cancellables)
    }

    func redrawNow() {
        redrawScheduled = false
        redraw(force: true)
    }

    private func scheduleRedraw() {
        guard !redrawScheduled else { return }
        redrawScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.redrawScheduled = false
            self.redraw()
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        onClick?()
    }

    private func redraw(force: Bool = false) {
        redrawScheduled = false
        let signature = renderSignature()
        if !force, signature == lastRenderSignature { return }
        lastRenderSignature = signature
        let image = buildImage()
        statusItem.button?.image = image
        statusItem.length = max(image.size.width + 4, 24)
        if let label = image.accessibilityDescription {
            statusItem.button?.setAccessibilityLabel(label)
        }
    }

    struct EffectiveMenuMetrics {
        var showCPU: Bool
        var showGPU: Bool
        var showMemory: Bool
        var showBattery: Bool
        var showNetwork: Bool
        var order: [MenuBarMetric]

        var isBrandOnly: Bool {
            !showCPU && !showGPU && !showMemory && !showBattery && !showNetwork
        }
    }

    static func effectiveMenuMetrics(settings: AppSettings, batteryIsPresent: Bool) -> EffectiveMenuMetrics {
        let showBattery = settings.menuBattery && batteryIsPresent
        return EffectiveMenuMetrics(showCPU: settings.menuCPU,
                                    showGPU: settings.menuGPU,
                                    showMemory: settings.menuMemory,
                                    showBattery: showBattery,
                                    showNetwork: settings.menuNetwork,
                                    order: settings.orderedMenuBarMetrics)
    }

    private func effectiveMenuMetrics() -> EffectiveMenuMetrics {
        Self.effectiveMenuMetrics(settings: AppSettings.shared, batteryIsPresent: hub.snapshot.batteryIsPresent)
    }

    private func renderSignature() -> String {
        let settings = AppSettings.shared
        let snapshot = hub.snapshot
        var parts: [String] = [
            "l:\(settings.resolvedMenuBarLayout.rawValue)",
            "c:\(settings.menuCompact)",
            "fs:\(settings.resolvedMenuBarFontStyle.rawValue)",
            "cm:\(settings.resolvedMenuBarColorMode.rawValue)",
            "fz:\(settings.menuBarFontSize)"
        ]
        let effective = effectiveMenuMetrics()
        parts.append(contentsOf: effective.order.map(\.rawValue))
        parts.append("brandOnly:\(effective.isBrandOnly)")
        if effective.showCPU { parts.append("cpu:\(Int(snapshot.cpuUsage * 100))") }
        if effective.showGPU { parts.append("gpu:\(Int(snapshot.gpuUtilization * 100))") }
        if effective.showMemory { parts.append("mem:\(Int(snapshot.memoryFraction * 100))") }
        if effective.showBattery {
            parts.append("bat:\(Int(snapshot.batteryPercentage * 100)):\(snapshot.batteryIsCharging)")
        }
        if effective.showNetwork {
            parts.append("dn:\(Formatters.rateCompact(snapshot.networkDownloadRate))")
            parts.append("up:\(Formatters.rateCompact(snapshot.networkUploadRate))")
        }
        return parts.joined(separator: "|")
    }

    private func buildImage() -> NSImage {
        let settings = AppSettings.shared
        let snapshot = hub.snapshot
        let effective = effectiveMenuMetrics()
        let input = MenuBarImageRenderer.Input(
            cpu: snapshot.cpuUsage,
            gpu: snapshot.gpuUtilization,
            mem: snapshot.memoryFraction,
            battery: snapshot.batteryIsPresent ? snapshot.batteryPercentage : nil,
            batteryCharging: snapshot.batteryIsCharging,
            down: snapshot.networkDownloadRate,
            up: snapshot.networkUploadRate,
            showCPU: effective.showCPU,
            showGPU: effective.showGPU,
            showMem: effective.showMemory,
            showBattery: effective.showBattery,
            showNet: effective.showNetwork,
            metricOrder: effective.order,
            height: Self.barHeight,
            layout: settings.resolvedMenuBarLayout,
            compact: settings.menuCompact,
            fontStyle: settings.resolvedMenuBarFontStyle,
            colorMode: settings.resolvedMenuBarColorMode,
            fontSize: CGFloat(settings.menuBarFontSize)
        )
        return MenuBarImageRenderer.render(input)
    }

}
