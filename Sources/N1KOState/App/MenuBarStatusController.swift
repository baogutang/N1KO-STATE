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
        parts.append(contentsOf: settings.orderedMenuBarMetrics.map(\.rawValue))
        if settings.menuCPU { parts.append("cpu:\(Int(snapshot.cpuUsage * 100))") }
        if settings.menuGPU { parts.append("gpu:\(Int(snapshot.gpuUtilization * 100))") }
        if settings.menuMemory { parts.append("mem:\(Int(snapshot.memoryFraction * 100))") }
        if settings.menuBattery, snapshot.batteryIsPresent {
            parts.append("bat:\(Int(snapshot.batteryPercentage * 100)):\(snapshot.batteryIsCharging)")
        }
        if settings.menuNetwork {
            parts.append("dn:\(Formatters.rateCompact(snapshot.networkDownloadRate))")
            parts.append("up:\(Formatters.rateCompact(snapshot.networkUploadRate))")
        }
        return parts.joined(separator: "|")
    }

    private func buildImage() -> NSImage {
        let settings = AppSettings.shared
        let snapshot = hub.snapshot
        var showCPU = settings.menuCPU
        var showGPU = settings.menuGPU
        let showMem = settings.menuMemory
        let showBat = settings.menuBattery
        let showNet = settings.menuNetwork
        if !showCPU && !showGPU && !showMem && !showBat && !showNet {
            showCPU = true
            showGPU = true
        }
        let input = MenuBarImageRenderer.Input(
            cpu: snapshot.cpuUsage,
            gpu: snapshot.gpuUtilization,
            mem: snapshot.memoryFraction,
            battery: snapshot.batteryIsPresent ? snapshot.batteryPercentage : nil,
            batteryCharging: snapshot.batteryIsCharging,
            down: snapshot.networkDownloadRate,
            up: snapshot.networkUploadRate,
            showCPU: showCPU,
            showGPU: showGPU,
            showMem: showMem,
            showBattery: showBat,
            showNet: showNet,
            metricOrder: settings.orderedMenuBarMetrics,
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
