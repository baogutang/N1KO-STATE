import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum FullscreenKind: String, Codable, Equatable {
    case native
    case pseudo
}

enum FullscreenClassification: String, Codable, Equatable {
    case ordinary
    case nativeFullscreen
    case pseudoFullscreen
    case unknown

    var fullscreenKind: FullscreenKind? {
        switch self {
        case .nativeFullscreen: return .native
        case .pseudoFullscreen: return .pseudo
        case .ordinary, .unknown: return nil
        }
    }
}

struct FullscreenEvidence: Equatable {
    let classification: FullscreenClassification
    let coverage: Double
    let ownerPID: pid_t?
    let sampledAtUptimeNanoseconds: UInt64

    static func ordinary(at uptime: UInt64 = DispatchTime.now().uptimeNanoseconds) -> Self {
        .init(classification: .ordinary, coverage: 0, ownerPID: nil,
              sampledAtUptimeNanoseconds: uptime)
    }
}

enum FullscreenEvidenceClassifier {
    static func classify(coverage: Double,
                         accessibilityFullscreen: Bool?,
                         hasRecentActiveSpaceSignal: Bool) -> FullscreenClassification {
        guard coverage >= FullscreenEvidenceSampler.minimumCoverage else { return .ordinary }
        return accessibilityFullscreen == true || hasRecentActiveSpaceSignal
            ? .nativeFullscreen
            : .pseudoFullscreen
    }
}

enum FullscreenEnvironmentPhase: Equatable {
    case desktop
    case entering
    case fullscreen(FullscreenKind)
    case revealing(FullscreenKind)
    case exiting
    case suspended

    var stableFullscreenKind: FullscreenKind? {
        switch self {
        case .fullscreen(let kind), .revealing(let kind): return kind
        case .desktop, .entering, .exiting, .suspended: return nil
        }
    }

    var isProvisionalOrFullscreen: Bool {
        switch self {
        case .entering, .fullscreen, .revealing, .exiting: return true
        case .desktop, .suspended: return false
        }
    }
}

/// Public-signal state machine. Native fullscreen exclusion is structural at
/// the window level; this state only controls reveal eligibility and the
/// fail-closed pseudo-fullscreen policy.
struct FullscreenEnvironmentStateMachine {
    private(set) var phase: FullscreenEnvironmentPhase = .desktop
    private var positiveKind: FullscreenKind?
    private var positiveSamples = 0
    private var negativeSamples = 0
    let requiredAgreementSamples: Int

    init(requiredAgreementSamples: Int = 2) {
        self.requiredAgreementSamples = max(requiredAgreementSamples, 1)
    }

    mutating func beginReconciliation() {
        positiveKind = nil
        positiveSamples = 0
        negativeSamples = 0
        switch phase {
        case .suspended:
            break
        case .fullscreen, .revealing, .exiting:
            phase = .exiting
        case .desktop, .entering:
            phase = .entering
        }
    }

    @discardableResult
    mutating func consume(_ evidence: FullscreenEvidence) -> FullscreenEnvironmentPhase {
        guard phase != .suspended else { return phase }

        if let kind = evidence.classification.fullscreenKind {
            negativeSamples = 0
            if positiveKind == kind {
                positiveSamples += 1
            } else {
                positiveKind = kind
                positiveSamples = 1
            }
            if positiveSamples >= requiredAgreementSamples {
                phase = .fullscreen(kind)
                positiveSamples = 0
            }
        } else if evidence.classification == .ordinary {
            positiveKind = nil
            positiveSamples = 0
            negativeSamples += 1
            if negativeSamples >= requiredAgreementSamples {
                phase = .desktop
                negativeSamples = 0
            }
        } else {
            positiveKind = nil
            positiveSamples = 0
            negativeSamples = 0
        }
        return phase
    }

    @discardableResult
    mutating func beginReveal() -> Bool {
        guard case .fullscreen(let kind) = phase else { return false }
        phase = .revealing(kind)
        return true
    }

    mutating func dismissReveal() {
        guard case .revealing(let kind) = phase else { return }
        phase = .fullscreen(kind)
    }

    mutating func suspend() {
        positiveKind = nil
        positiveSamples = 0
        negativeSamples = 0
        phase = .suspended
    }

    mutating func resume() {
        guard phase == .suspended else { return }
        phase = .entering
    }
}

struct DisplayDescriptor: Equatable, Identifiable {
    let displayID: CGDirectDisplayID
    let uuid: String
    let localizedName: String
    let quartzBounds: CGRect
    let appKitFrame: CGRect
    let backingScaleFactor: CGFloat
    let safeAreaTop: CGFloat

    var id: String { uuid }
    var hasCameraHousing: Bool { safeAreaTop > 0.5 }
}

enum DisplayCatalog {
    static func current() -> [DisplayDescriptor] {
        NSScreen.screens.compactMap(descriptor(for:))
    }

    static func descriptor(for screen: NSScreen) -> DisplayDescriptor? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        let uuid: String
        if let value = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
           let string = CFUUIDCreateString(nil, value) {
            uuid = string as String
        } else {
            uuid = "display-\(displayID)"
        }
        return DisplayDescriptor(
            displayID: displayID,
            uuid: uuid,
            localizedName: screen.localizedName,
            quartzBounds: CGDisplayBounds(displayID),
            appKitFrame: screen.frame,
            backingScaleFactor: screen.backingScaleFactor,
            safeAreaTop: screen.safeAreaInsets.top
        )
    }

    static func target(preferredUUID: String, pointer: NSPoint? = nil,
                       displays: [DisplayDescriptor] = current()) -> DisplayDescriptor? {
        if preferredUUID != AppSettings.automaticDisplaySelection,
           let selected = displays.first(where: { $0.uuid == preferredUUID }) {
            return selected
        }
        if let pointer,
           let pointed = displays.first(where: { $0.appKitFrame.contains(pointer) }) {
            return pointed
        }
        guard let main = NSScreen.main.flatMap(descriptor(for:)) else { return displays.first }
        return displays.first(where: { $0.uuid == main.uuid }) ?? displays.first
    }
}

enum DisplayCoordinateNormalizer {
    /// Maps an AppKit global point into the Quartz coordinate space for the
    /// same display. Geometry is paired by display ID/UUID, never by directly
    /// comparing NSScreen.frame with a CGWindow bounds dictionary.
    static func quartzPoint(fromAppKit point: CGPoint, on display: DisplayDescriptor) -> CGPoint {
        guard display.appKitFrame.width > 0, display.appKitFrame.height > 0 else {
            return display.quartzBounds.origin
        }
        let x = (point.x - display.appKitFrame.minX) / display.appKitFrame.width
        let yFromTop = (display.appKitFrame.maxY - point.y) / display.appKitFrame.height
        return CGPoint(
            x: display.quartzBounds.minX + x * display.quartzBounds.width,
            y: display.quartzBounds.minY + yFromTop * display.quartzBounds.height
        )
    }

    static func coverage(of windowBounds: CGRect, on display: DisplayDescriptor) -> Double {
        guard display.quartzBounds.width > 0, display.quartzBounds.height > 0 else { return 0 }
        let intersection = windowBounds.intersection(display.quartzBounds)
        guard !intersection.isNull else { return 0 }
        let displayArea = display.quartzBounds.width * display.quartzBounds.height
        return Double((intersection.width * intersection.height) / displayArea)
    }

    static func topEdgeTriggerRect(on display: DisplayDescriptor, width: CGFloat = 260,
                                   depth: CGFloat = 3) -> CGRect {
        CGRect(x: display.appKitFrame.midX - width / 2,
               y: display.appKitFrame.maxY - depth,
               width: width,
               height: depth)
    }
}

/// Samples only on transition requests and bounded retries. It contains no
/// timer or polling loop and uses public Core Graphics and Accessibility APIs.
final class FullscreenEvidenceSampler: @unchecked Sendable {
    static let minimumCoverage = 0.985
    static let activeSpaceCorrelationNanoseconds: UInt64 = 2_000_000_000

    private var lastActiveSpaceSignal: UInt64?
    private let processIDOverride: pid_t?
    private let lock = NSLock()

    init(processIDOverride: pid_t? = nil) {
        self.processIDOverride = processIDOverride
    }

    func noteActiveSpaceChange(at uptime: UInt64 = DispatchTime.now().uptimeNanoseconds) {
        lock.lock()
        lastActiveSpaceSignal = uptime
        lock.unlock()
    }

    func sample(display: DisplayDescriptor,
                now: UInt64 = DispatchTime.now().uptimeNanoseconds) -> FullscreenEvidence {
        if let processIDOverride {
            return sample(display: display,
                          processID: processIDOverride,
                          relatedProcessIDs: [processIDOverride],
                          now: now)
        }
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return FullscreenEvidence(classification: .unknown, coverage: 0, ownerPID: nil,
                                      sampledAtUptimeNanoseconds: now)
        }
        return sample(display: display,
                      processID: app.processIdentifier,
                      relatedProcessIDs: relatedProcessIDs(for: app),
                      now: now)
    }

    private func sample(display: DisplayDescriptor,
                        processID: pid_t,
                        relatedProcessIDs: Set<pid_t>,
                        now: UInt64) -> FullscreenEvidence {
        guard let window = leadingLayerZeroWindow(candidatePIDs: relatedProcessIDs, display: display) else {
            return FullscreenEvidence(classification: .ordinary, coverage: 0, ownerPID: processID,
                                      sampledAtUptimeNanoseconds: now)
        }

        let coverage = DisplayCoordinateNormalizer.coverage(of: window.bounds, on: display)
        guard coverage >= Self.minimumCoverage else {
            return FullscreenEvidence(classification: .ordinary, coverage: coverage,
                                      ownerPID: window.ownerPID, sampledAtUptimeNanoseconds: now)
        }

        let axFullscreen = accessibilityFullscreen(processID: processID)
        lock.lock()
        let activeSpaceSignal = lastActiveSpaceSignal
        lock.unlock()
        let correlatedSpaceChange = activeSpaceSignal.map {
            now >= $0 && now - $0 <= Self.activeSpaceCorrelationNanoseconds
        } ?? false
        let classification = FullscreenEvidenceClassifier.classify(
            coverage: coverage,
            accessibilityFullscreen: axFullscreen,
            hasRecentActiveSpaceSignal: correlatedSpaceChange
        )
        return FullscreenEvidence(classification: classification, coverage: coverage,
                                  ownerPID: window.ownerPID, sampledAtUptimeNanoseconds: now)
    }

    private func relatedProcessIDs(for app: NSRunningApplication) -> Set<pid_t> {
        var values: Set<pid_t> = [app.processIdentifier]
        if let bundleIdentifier = app.bundleIdentifier {
            for related in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
                values.insert(related.processIdentifier)
            }
        }
        return values
    }

    private func leadingLayerZeroWindow(candidatePIDs: Set<pid_t>, display: DisplayDescriptor)
        -> (ownerPID: pid_t, bounds: CGRect)? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        var leading: (ownerPID: pid_t, bounds: CGRect, coverage: Double)?
        for info in windowList {
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            guard layer == 0,
                  let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let ownerPID = pid_t(pidNumber.int32Value)
            guard candidatePIDs.contains(ownerPID),
                  let dictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { continue }
            let coverage = DisplayCoordinateNormalizer.coverage(of: bounds, on: display)
            if leading == nil || coverage > leading!.coverage {
                leading = (ownerPID, bounds, coverage)
            }
        }
        return leading.map { ($0.ownerPID, $0.bounds) }
    }

    private func accessibilityFullscreen(processID: pid_t) -> Bool? {
        guard AXIsProcessTrusted() else { return nil }
        let application = AXUIElementCreateApplication(processID)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application, kAXFocusedWindowAttribute as CFString, &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else { return nil }

        let window = unsafeBitCast(focusedValue, to: AXUIElement.self)
        var fullscreenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window, "AXFullScreen" as CFString, &fullscreenValue
        ) == .success else { return nil }
        return fullscreenValue as? Bool
    }
}
