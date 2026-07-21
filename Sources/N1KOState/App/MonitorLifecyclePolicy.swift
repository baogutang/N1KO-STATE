import AppKit
import Foundation

struct MonitorLifecycleState: Equatable {
    var screenSleeping = false
    var sessionActive = true
    var applicationOccluded = false
    var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    var thermalState = ProcessInfo.processInfo.thermalState
    var wakeGraceUntilUptimeNanoseconds: UInt64 = 0

    var presentationAllowed: Bool {
        !screenSleeping && sessionActive
    }

    func isInWakeGrace(now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Bool {
        now < wakeGraceUntilUptimeNanoseconds
    }
}

/// Centralizes lifecycle signals used by sampling policy. Safety acquisition is
/// deliberately not disabled by presentation suspension.
final class MonitorLifecyclePolicy {
    private(set) var state = MonitorLifecycleState()
    var onChange: ((MonitorLifecycleState, MonitorLifecycleState) -> Void)?

    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default

        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.mutate { $0.screenSleeping = true }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.mutate {
                $0.screenSleeping = false
                $0.wakeGraceUntilUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
                    &+ 2_000_000_000
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.mutate { $0.sessionActive = false }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.mutate {
                $0.sessionActive = true
                $0.wakeGraceUntilUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
                    &+ 2_000_000_000
            }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeOcclusionStateNotification,
                                            object: NSApp,
                                            queue: .main) { [weak self] _ in
            self?.mutate { $0.applicationOccluded = !NSApp.occlusionState.contains(.visible) }
        })
        observers.append(center.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange,
                                            object: nil,
                                            queue: .main) { [weak self] _ in
            self?.mutate { $0.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled }
        })
        observers.append(center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                            object: nil,
                                            queue: .main) { [weak self] _ in
            self?.mutate { $0.thermalState = ProcessInfo.processInfo.thermalState }
        })
    }

    func stop() {
        let workspace = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default
        for observer in observers {
            workspace.removeObserver(observer)
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func mutate(_ body: (inout MonitorLifecycleState) -> Void) {
        let previous = state
        body(&state)
        guard state != previous else { return }
        onChange?(previous, state)
    }

    deinit {
        stop()
    }
}
