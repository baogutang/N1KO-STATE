import AppKit

open class AgentInteractivePanel: NSPanel {
    public var onCancel: (() -> Void)?

    open override var canBecomeKey: Bool { true }
    open override var canBecomeMain: Bool { false }

    open override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    open override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp:
            let location = event.locationInWindow
            if contentView?.hitTest(location) == nil {
                let screenLocation = convertPoint(toScreen: location)
                ignoresMouseEvents = true
                DispatchQueue.main.async { [weak self] in
                    self?.repostMouseEvent(event, at: screenLocation)
                }
                return
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    private func repostMouseEvent(_ event: NSEvent, at appKitScreenLocation: NSPoint) {
        let type: CGEventType
        switch event.type {
        case .leftMouseDown: type = .leftMouseDown
        case .leftMouseUp: type = .leftMouseUp
        case .rightMouseDown: type = .rightMouseDown
        case .rightMouseUp: type = .rightMouseUp
        default: return
        }
        let button: CGMouseButton = event.type == .rightMouseDown || event.type == .rightMouseUp
            ? .right
            : .left
        let desktopBounds = NSScreen.screens.map(\.frame).reduce(CGRect.null) { $0.union($1) }
        let quartzLocation = desktopBounds.isNull
            ? appKitScreenLocation
            : CGPoint(x: appKitScreenLocation.x, y: desktopBounds.maxY - appKitScreenLocation.y)
        guard let replay = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: quartzLocation,
            mouseButton: button
        ) else { return }
        replay.setIntegerValueField(.eventSourceUserData, value: 0x4E314B4F)
        replay.post(tap: .cghidEventTap)
    }

    func applyCommonConfiguration() {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        level = .mainMenu + 3
    }
}

/// Persistent ordinary-Space Island. The absence of fullScreenAuxiliary is a
/// shipping invariant, not a detector-driven workaround.
public final class DesktopIslandPanel: AgentInteractivePanel {
    public init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        applyCommonConfiguration()
        // `canJoinAllSpaces` still exposed this panel in a native fullscreen
        // Space on macOS 15.7.7. `moveToActiveSpace` keeps one persistent window
        // movable across ordinary Spaces while fullScreenNone structurally
        // prevents fullscreen co-existence.
        collectionBehavior = [.moveToActiveSpace, .stationary, .ignoresCycle, .fullScreenNone]
        orderOut(nil)
    }

    required init?(coder: NSCoder) { nil }
}

/// Lazily-created, normally hidden panel used only after a deliberate dwell in
/// a stable fullscreen state.
public final class FullscreenRevealPanel: AgentInteractivePanel {
    public init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        applyCommonConfiguration()
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        level = .popUpMenu
        orderOut(nil)
    }

    required init?(coder: NSCoder) { nil }
}

/// User-created detached companion. It remains an ordinary-Space window and
/// therefore follows the same structural fullscreen exclusion as the desktop
/// Island instead of joining fullscreen Spaces implicitly.
public final class DetachedIslandPanel: AgentInteractivePanel {
    public init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        applyCommonConfiguration()
        collectionBehavior = [.moveToActiveSpace, .stationary, .ignoresCycle, .fullScreenNone]
        isMovableByWindowBackground = true
        level = .floating
        orderOut(nil)
    }

    required init?(coder: NSCoder) { nil }
}
