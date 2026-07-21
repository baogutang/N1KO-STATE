import AppKit
import CoreGraphics
import Darwin
import Foundation
import N1KOWindowCore

private struct HarnessResult: Codable {
    let completed: Bool
    let cyclesRequested: Int
    let cyclesCompleted: Int
    let fullscreenSamples: Int
    let desktopFramesObservedAfterDidEnter: Int
    let desktopRestoreFailures: Int
    let desktopHasFullScreenAuxiliary: Bool
    let desktopHasFullScreenNone: Bool
    let revealPanelConstructed: Bool
    let elapsedSeconds: Double
    let displayID: UInt32
    let displayBounds: CGRect
    let screenFrame: CGRect
    let screenSafeAreaTop: CGFloat
    let failure: String?
}

private final class HarnessDelegate: NSObject, NSApplicationDelegate {
    private let cyclesRequested: Int
    private let outputURL: URL
    private var primary: NSWindow!
    private var desktop: DesktopIslandPanel!
    private var screen: NSScreen!
    private var displayID: CGDirectDisplayID = 0
    private var cyclesCompleted = 0
    private var fullscreenSamples = 0
    private var desktopFramesInFullscreen = 0
    private var restoreFailures = 0
    private var notificationTokens: [NSObjectProtocol] = []
    private var timeout: DispatchWorkItem?
    private var startedAt = DispatchTime.now().uptimeNanoseconds

    init(cycles: Int, outputURL: URL) {
        cyclesRequested = max(cycles, 1)
        self.outputURL = outputURL
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let target = NSScreen.main ?? NSScreen.screens.first,
              let number = target.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                as? NSNumber else {
            finish(failure: "No target NSScreen")
            return
        }
        screen = target
        displayID = CGDirectDisplayID(number.uint32Value)
        startedAt = DispatchTime.now().uptimeNanoseconds

        NSApp.setActivationPolicy(.regular)
        installMenu()
        primary = NSWindow(
            contentRect: NSRect(x: target.frame.midX - 360, y: target.frame.midY - 240,
                                width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false,
            screen: target
        )
        primary.title = "N1KO WP4 Native Fullscreen Harness"
        primary.collectionBehavior = [.fullScreenPrimary]
        primary.isReleasedWhenClosed = false
        let primaryContent = NSView(frame: primary.contentLayoutRect)
        primaryContent.wantsLayer = true
        primaryContent.layer?.backgroundColor = NSColor(calibratedRed: 0.05, green: 0.07,
                                                         blue: 0.12, alpha: 1).cgColor
        primary.contentView = primaryContent

        desktop = DesktopIslandPanel()
        desktop.isOpaque = true
        desktop.backgroundColor = NSColor(calibratedRed: 0.36, green: 0.35, blue: 0.90, alpha: 1)
        desktop.hasShadow = false
        desktop.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 264, height: 46))
        desktop.setFrame(NSRect(x: target.frame.midX - 132, y: target.frame.maxY - 52,
                                width: 264, height: 46), display: true)

        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: NSWindow.didEnterFullScreenNotification, object: primary, queue: .main
        ) { [weak self] _ in self?.didEnterFullscreen() })
        notificationTokens.append(center.addObserver(
            forName: NSWindow.didExitFullScreenNotification, object: primary, queue: .main
        ) { [weak self] _ in self?.didExitFullscreen() })

        NSApp.activate(ignoringOtherApps: true)
        primary.makeKeyAndOrderFront(nil)
        desktop.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.ensureDesktopVisible(attemptsRemaining: 20)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func installMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        main.addItem(applicationItem)
        let applicationMenu = NSMenu()
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        applicationMenu.addItem(quit)
        applicationItem.submenu = applicationMenu
        NSApp.mainMenu = main
    }

    private func beginEnter() {
        armTimeout(label: "enter", cycle: cyclesCompleted)
        primary.toggleFullScreen(nil)
    }

    private func ensureDesktopVisible(attemptsRemaining: Int) {
        guard !windowIsOnScreen(desktop.windowNumber) else {
            beginEnter()
            return
        }
        guard attemptsRemaining > 0 else {
            finish(failure: "Desktop panel was not visible before cycle 1")
            return
        }
        desktop.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] in
            self?.ensureDesktopVisible(attemptsRemaining: attemptsRemaining - 1)
        }
    }

    private func didEnterFullscreen() {
        cancelTimeout()
        for sample in 0..<3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(sample) * 0.02) { [weak self] in
                guard let self else { return }
                self.fullscreenSamples += 1
                if self.windowIsOnScreen(self.desktop.windowNumber) {
                    self.desktopFramesInFullscreen += 1
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { [weak self] in
            guard let self else { return }
            self.armTimeout(label: "exit", cycle: self.cyclesCompleted)
            self.primary.toggleFullScreen(nil)
        }
    }

    private func didExitFullscreen() {
        cancelTimeout()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            if !self.windowIsOnScreen(self.desktop.windowNumber) {
                self.restoreFailures += 1
            }
            self.cyclesCompleted += 1
            if self.cyclesCompleted % 10 == 0 || self.cyclesCompleted == self.cyclesRequested {
                print("WP4_NATIVE_PROGRESS cycles=\(self.cyclesCompleted)/\(self.cyclesRequested) " +
                      "fullscreenSamples=\(self.fullscreenSamples) " +
                      "desktopFrames=\(self.desktopFramesInFullscreen) " +
                      "restoreFailures=\(self.restoreFailures)")
                fflush(stdout)
            }
            if self.cyclesCompleted >= self.cyclesRequested {
                self.finish(failure: nil)
            } else {
                // WindowServer can publish didExit before the ordinary Space
                // accepts a new fullscreen request. A short stabilization
                // grace keeps the harness from testing a dropped toggle.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                    self?.beginEnter()
                }
            }
        }
    }

    private func armTimeout(label: String, cycle: Int) {
        cancelTimeout()
        let item = DispatchWorkItem { [weak self] in
            self?.finish(failure: "Timed out waiting to \(label) fullscreen at cycle \(cycle)")
        }
        timeout = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
    }

    private func cancelTimeout() {
        timeout?.cancel()
        timeout = nil
    }

    private func windowIsOnScreen(_ windowNumber: Int) -> Bool {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                as? [[String: Any]] else { return false }
        return list.contains {
            ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == windowNumber
        }
    }

    private func finish(failure: String?) {
        cancelTimeout()
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000_000
        let result = HarnessResult(
            completed: failure == nil && cyclesCompleted == cyclesRequested,
            cyclesRequested: cyclesRequested,
            cyclesCompleted: cyclesCompleted,
            fullscreenSamples: fullscreenSamples,
            desktopFramesObservedAfterDidEnter: desktopFramesInFullscreen,
            desktopRestoreFailures: restoreFailures,
            desktopHasFullScreenAuxiliary: desktop?.collectionBehavior.contains(.fullScreenAuxiliary) ?? false,
            desktopHasFullScreenNone: desktop?.collectionBehavior.contains(.fullScreenNone) ?? false,
            revealPanelConstructed: false,
            elapsedSeconds: elapsed,
            displayID: displayID,
            displayBounds: displayID == 0 ? .zero : CGDisplayBounds(displayID),
            screenFrame: screen?.frame ?? .zero,
            screenSafeAreaTop: screen?.safeAreaInsets.top ?? 0,
            failure: failure
        )
        do {
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONEncoder.pretty.encode(result)
            try data.write(to: outputURL, options: .atomic)
            print(String(data: data, encoding: .utf8) ?? "")
        } catch {
            fputs("Failed to write harness result: \(error)\n", stderr)
            Darwin.exit(2)
        }
        fflush(stdout)
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        desktop?.orderOut(nil)
        primary?.orderOut(nil)
        Darwin.exit(result.completed
                    && desktopFramesInFullscreen == 0
                    && restoreFailures == 0
                    && result.desktopHasFullScreenNone
                    && !result.desktopHasFullScreenAuxiliary ? 0 : 1)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

@main
private enum N1KOWP4FullscreenHarnessMain {
    static func main() {
        let environment = ProcessInfo.processInfo.environment
        let cycles = Int(environment["N1KO_NATIVE_FULLSCREEN_CYCLES"] ?? "100") ?? 100
        let output = environment["N1KO_NATIVE_FULLSCREEN_OUTPUT"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("n1ko-wp4-fullscreen.json")
        let application = NSApplication.shared
        let delegate = HarnessDelegate(cycles: cycles, outputURL: output)
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
