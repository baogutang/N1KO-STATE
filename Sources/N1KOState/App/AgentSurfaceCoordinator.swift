import AppKit
import Combine
import N1KOAgentCore
import N1KOWindowCore

// N1KO modification notice:
// The route priority, completion presentation lifecycle, measured panel sizing,
// and detached Buddy anchor/placement behavior in this file are adapted from
// Apache-2.0 Ping Island commit da130d6. N1KO replaces its window ownership and
// fullscreen path with the public-API dual-window coordinator defined here.

struct AgentSurfaceProjection: Equatable {
    let generation: UInt64
    let generatedAt: Date
    let sessions: [AgentSessionSnapshot]
    let primarySession: AgentSessionSnapshot?
    let activeCount: Int
    let attentionCount: Int
    let completionCount: Int
    let usage: AgentUsage
    let usageWindows: [AgentProvider: [AgentUsageWindow]]
    let shouldPresentIsland: Bool

    static let empty = AgentSurfaceProjection(
        generation: 0,
        generatedAt: Date(timeIntervalSince1970: 0),
        sessions: [],
        primarySession: nil,
        activeCount: 0,
        attentionCount: 0,
        completionCount: 0,
        usage: AgentUsage(),
        usageWindows: [:],
        shouldPresentIsland: false
    )

    static func make(snapshot: AgentSnapshot, now: Date = Date()) -> Self {
        let visible = snapshot.sessions
            .filter { $0.phase != .archived }
            .sorted { lhs, rhs in
                let lhsAction = requiresAction(lhs)
                let rhsAction = requiresAction(rhs)
                if lhsAction != rhsAction { return lhsAction }
                if lhs.phase.isTerminal != rhs.phase.isTerminal { return !lhs.phase.isTerminal }
                return lhs.lastActivityAt > rhs.lastActivityAt
            }
        let activeCount = visible.filter { !$0.phase.isTerminal }.count
        let attentionCount = visible.filter(requiresAction).count
        let recentCutoff = now.addingTimeInterval(-10 * 60)
        let completions = visible.filter {
            $0.phase == .completed && ($0.completedAt ?? $0.lastActivityAt) >= recentCutoff
        }
        let primary = visible.first(where: requiresAction)
            ?? visible.first(where: { !$0.phase.isTerminal })
            ?? completions.first
        let usage = snapshot.usage.byProvider.values.reduce(AgentUsage()) { partial, value in
            AgentUsage(
                inputTokens: partial.inputTokens + value.inputTokens,
                cachedInputTokens: partial.cachedInputTokens + value.cachedInputTokens,
                outputTokens: partial.outputTokens + value.outputTokens
            )
        }
        return AgentSurfaceProjection(
            generation: snapshot.generation,
            generatedAt: snapshot.generatedAt,
            sessions: Array(visible.prefix(12)),
            primarySession: primary,
            activeCount: activeCount,
            attentionCount: attentionCount,
            completionCount: completions.count,
            usage: usage,
            usageWindows: snapshot.usage.providerWindows,
            shouldPresentIsland: primary != nil
        )
    }

    private static func requiresAction(_ session: AgentSessionSnapshot) -> Bool {
        if session.intervention != nil || session.phase.needsAttention { return true }
        switch session.attention {
        case .approval, .question, .failure: return true
        case .completion, .none: return false
        }
    }
}

struct AgentDisplayOption: Identifiable, Equatable {
    let id: String
    let title: String
    let isNotched: Bool
}

struct AgentSurfaceResponseRequest {
    let provider: AgentProvider
    let sessionID: String
    let requestID: String
    let ownerID: String
    let capability: String
    let action: AgentResponseAction
}

/// Ping-Island's ambient completion policy, translated to N1KO's explicit
/// terminal phases. Completions are one-shot, recent, and suppressed while a
/// different session is actively working or waiting on the user.
enum AgentCompletionNotificationPolicy {
    static let recencyWindow: TimeInterval = 60

    static func shouldQueue(
        _ session: AgentSessionSnapshot,
        previous: AgentSessionSnapshot?,
        sessions: [AgentSessionSnapshot],
        now: Date
    ) -> Bool {
        guard session.phase == .completed else { return false }
        guard previous?.phase != .completed else { return false }
        guard hasRecentActivity(session, now: now) else { return false }
        if previous == nil {
            guard !session.wasRestored,
                  now.timeIntervalSince(session.createdAt) <= recencyWindow else { return false }
        }
        return !hasBlockingActiveSession(for: session, in: sessions)
    }

    static func isPresentable(
        _ session: AgentSessionSnapshot,
        sessions: [AgentSessionSnapshot],
        now: Date
    ) -> Bool {
        session.phase == .completed
            && hasRecentActivity(session, now: now)
            && !hasBlockingActiveSession(for: session, in: sessions)
    }

    static func hasRecentActivity(_ session: AgentSessionSnapshot, now: Date) -> Bool {
        now.timeIntervalSince(session.lastActivityAt) <= recencyWindow
    }

    static func hasBlockingActiveSession(
        for session: AgentSessionSnapshot,
        in sessions: [AgentSessionSnapshot]
    ) -> Bool {
        sessions.contains { candidate in
            guard candidate.id != session.id else { return false }
            switch candidate.phase {
            case .starting, .processing, .waitingForApproval, .waitingForAnswer:
                return true
            case .completed, .interrupted, .failed, .ended, .archived:
                return false
            }
        }
    }
}

final class AgentSurfaceModel: ObservableObject {
    @Published private(set) var projection: AgentSurfaceProjection
    @Published var isExpanded = false {
        didSet {
            if isExpanded {
                if expansionTrigger == nil { expansionTrigger = .click }
            } else if expansionTrigger != nil {
                expansionTrigger = nil
            }
        }
    }
    @Published private(set) var expansionTrigger: AgentIslandExpansionTrigger?
    @Published private(set) var responseStatus: String?
    @Published private(set) var displayOptions: [AgentDisplayOption] = []
    @Published private(set) var selectedSessionID: String?
    @Published private(set) var notificationSessionID: String?
    @Published private(set) var selectedSessionIndex = 0
    @Published private(set) var openedMeasuredContentHeight: CGFloat?
    @Published private(set) var detachedBubblePlacement: AgentDetachedBubblePlacement = .topLeft

    private(set) var sourceSnapshot: AgentSnapshot
    private var completionQueue: [String] = []
    private var consumedCompletionKeys = Set<String>()
    private var notificationDismissWorkItem: DispatchWorkItem?
    private var dismissNotificationOnHoverExit = false

    init(snapshot: AgentSnapshot = .empty) {
        sourceSnapshot = snapshot
        projection = AgentSurfaceProjection.make(snapshot: snapshot)
    }

    func expand(reason: AgentIslandExpansionTrigger) {
        if reason != .notification { discardAmbientCompletions() }
        expansionTrigger = reason
        isExpanded = true
    }

    func collapse() {
        notificationDismissWorkItem?.cancel()
        notificationDismissWorkItem = nil
        dismissNotificationOnHoverExit = false
        expansionTrigger = nil
        isExpanded = false
        selectedSessionID = nil
        notificationSessionID = nil
        completionQueue.removeAll()
        openedMeasuredContentHeight = nil
    }

    func route(for surface: AgentSurfaceKind) -> AgentIslandRoute {
        if let selectedSessionID,
           projection.sessions.contains(where: { $0.id == selectedSessionID }) {
            return .conversation(selectedSessionID)
        }
        if expansionTrigger == .pinnedList {
            return .sessionList
        }
        if let notificationSessionID,
           let session = projection.sessions.first(where: { $0.id == notificationSessionID }) {
            return session.needsAttention
                ? .attention(notificationSessionID)
                : .completion(notificationSessionID)
        }
        if let attention = projection.sessions.first(where: { $0.needsAttention }) {
            return .attention(attention.id)
        }
        if surface == .fullscreenReveal || expansionTrigger == .hover {
            return .hoverDashboard
        }
        return .sessionList
    }

    func detachedRoute(for mode: AgentDetachedBubbleMode) -> AgentIslandRoute {
        if mode == .pinnedList { return .sessionList }
        if let notificationSessionID,
           let session = projection.sessions.first(where: { $0.id == notificationSessionID }) {
            return session.needsAttention
                ? .attention(notificationSessionID)
                : .completion(notificationSessionID)
        }
        if let selectedSessionID,
           projection.sessions.contains(where: { $0.id == selectedSessionID }) {
            return .conversation(selectedSessionID)
        }
        if let attention = projection.sessions.first(where: { $0.needsAttention }) {
            return .attention(attention.id)
        }
        return .hoverDashboard
    }

    func setDetachedBubblePlacement(_ placement: AgentDetachedBubblePlacement) {
        if detachedBubblePlacement != placement { detachedBubblePlacement = placement }
    }

    func session(id: String) -> AgentSessionSnapshot? {
        projection.sessions.first(where: { $0.id == id })
    }

    func openConversation(_ session: AgentSessionSnapshot) {
        discardAmbientCompletions()
        openedMeasuredContentHeight = nil
        selectedSessionID = session.id
        notificationSessionID = nil
        expansionTrigger = .click
        isExpanded = true
    }

    func showSessionList() {
        discardAmbientCompletions()
        openedMeasuredContentHeight = nil
        selectedSessionID = nil
        notificationSessionID = nil
        expansionTrigger = .pinnedList
        isExpanded = true
    }

    func updateOpenedMeasuredContentHeight(_ height: CGFloat?) {
        let sanitized = height.flatMap { $0 > 0 ? ceil($0) : nil }
        guard sanitized != openedMeasuredContentHeight else { return }
        openedMeasuredContentHeight = sanitized
    }

    func dismissNotification(keepOpen: Bool = false) {
        notificationDismissWorkItem?.cancel()
        notificationDismissWorkItem = nil
        dismissNotificationOnHoverExit = false
        if let notificationSessionID,
           let session = projection.sessions.first(where: { $0.id == notificationSessionID }),
           session.phase == .completed {
            markCompletionConsumed(session)
        }
        if !completionQueue.isEmpty { completionQueue.removeFirst() }
        notificationSessionID = completionQueue.first
        if notificationSessionID == nil {
            if keepOpen {
                showSessionList()
            } else if expansionTrigger == .notification {
                collapse()
            }
        }
    }

    func setNotificationHovered(_ hovering: Bool) {
        guard notificationSessionID != nil else {
            dismissNotificationOnHoverExit = false
            return
        }
        if hovering {
            dismissNotificationOnHoverExit = true
            notificationDismissWorkItem?.cancel()
            notificationDismissWorkItem = nil
        } else if dismissNotificationOnHoverExit {
            dismissNotification(keepOpen: false)
        }
    }

    private func scheduleNotificationDismiss(after delay: TimeInterval = 5.0) {
        notificationDismissWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.notificationDismissWorkItem = nil
            self?.dismissNotification(keepOpen: false)
        }
        notificationDismissWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func moveSelection(_ delta: Int) {
        guard !projection.sessions.isEmpty else { return }
        selectedSessionIndex = min(max(selectedSessionIndex + delta, 0), projection.sessions.count - 1)
    }

    func selectedSession() -> AgentSessionSnapshot? {
        guard projection.sessions.indices.contains(selectedSessionIndex) else { return nil }
        return projection.sessions[selectedSessionIndex]
    }

    @discardableResult
    func consume(_ snapshot: AgentSnapshot, now: Date = Date()) -> Bool {
        guard snapshot.generation != sourceSnapshot.generation || snapshot != sourceSnapshot else {
            return false
        }
        let previousByID = Dictionary(uniqueKeysWithValues: sourceSnapshot.sessions.map { ($0.id, $0) })
        sourceSnapshot = snapshot
        projection = AgentSurfaceProjection.make(snapshot: snapshot, now: now)
        let completionTransitions = projection.sessions.filter { session in
            session.phase == .completed && previousByID[session.id]?.phase != .completed
        }
        let newlyCompleted = completionTransitions.filter { session in
            !isCompletionConsumed(session)
                && AgentCompletionNotificationPolicy.shouldQueue(
                    session,
                    previous: previousByID[session.id],
                    sessions: projection.sessions,
                    now: now
                )
        }
        let newlyAttentive = projection.sessions.filter { session in
            guard session.needsAttention else { return false }
            return previousByID[session.id]?.needsAttention != true
        }
        let candidates = newlyAttentive + newlyCompleted
        for completion in completionTransitions where !newlyCompleted.contains(where: { $0.id == completion.id }) {
            if AgentCompletionNotificationPolicy.hasBlockingActiveSession(
                for: completion,
                in: projection.sessions
            ) {
                markCompletionConsumed(completion)
            }
        }
        completionQueue = completionQueue.filter { queuedID in
            guard let session = projection.sessions.first(where: { $0.id == queuedID }) else { return false }
            let keep = !isCompletionConsumed(session)
                && AgentCompletionNotificationPolicy.isPresentable(
                    session,
                    sessions: projection.sessions,
                    now: now
                )
            if !keep { markCompletionConsumed(session) }
            return keep
        }
        if let notificationSessionID,
           let current = projection.sessions.first(where: { $0.id == notificationSessionID }),
           current.phase == .completed,
           (!AgentCompletionNotificationPolicy.isPresentable(
               current,
               sessions: projection.sessions,
               now: now
           ) || isCompletionConsumed(current)) {
            markCompletionConsumed(current)
            self.notificationSessionID = nil
        } else if let notificationSessionID,
                  !projection.sessions.contains(where: {
                      $0.id == notificationSessionID && ($0.needsAttention || $0.phase == .completed)
                  }) {
            self.notificationSessionID = nil
        }

        if !candidates.isEmpty && !AppSettings.shared.agentNotificationsTemporarilyMuted {
            if let attention = newlyAttentive.first {
                notificationDismissWorkItem?.cancel()
                notificationDismissWorkItem = nil
                dismissNotificationOnHoverExit = false
                completionQueue.removeAll()
                notificationSessionID = attention.id
            } else if !(isExpanded && expansionTrigger != .notification) {
                for candidate in newlyCompleted where !completionQueue.contains(candidate.id) {
                    completionQueue.append(candidate.id)
                }
                notificationSessionID = notificationSessionID ?? completionQueue.first
            }

            if let notificationSessionID,
               AppSettings.shared.agentNotificationAutoOpen {
                expansionTrigger = .notification
                isExpanded = true
                if projection.sessions.first(where: { $0.id == notificationSessionID })?.needsAttention != true {
                    scheduleNotificationDismiss()
                }
            }
        }
        if let selectedSessionID,
           !projection.sessions.contains(where: { $0.id == selectedSessionID }) {
            self.selectedSessionID = nil
        }
        if notificationSessionID == nil,
           expansionTrigger == .notification,
           newlyAttentive.isEmpty,
           newlyCompleted.isEmpty {
            collapse()
        }
        selectedSessionIndex = min(selectedSessionIndex, max(projection.sessions.count - 1, 0))
        responseStatus = nil
        AgentSurfaceDiagnostics.event(.snapshotComposition)
        PerformanceDiagnostics.event(.agentSurfaceComposition)
        return true
    }

    private func completionKey(_ session: AgentSessionSnapshot) -> String {
        let date = session.completedAt ?? session.lastActivityAt
        let milliseconds = Int64((date.timeIntervalSince1970 * 1_000).rounded())
        return "\(session.id):\(milliseconds)"
    }

    private func isCompletionConsumed(_ session: AgentSessionSnapshot) -> Bool {
        consumedCompletionKeys.contains(completionKey(session))
    }

    private func markCompletionConsumed(_ session: AgentSessionSnapshot) {
        consumedCompletionKeys.insert(completionKey(session))
    }

    private func discardAmbientCompletions() {
        for id in completionQueue {
            if let session = projection.sessions.first(where: { $0.id == id }) {
                markCompletionConsumed(session)
            }
        }
        if let notificationSessionID,
           let session = projection.sessions.first(where: { $0.id == notificationSessionID }),
           session.phase == .completed {
            markCompletionConsumed(session)
            self.notificationSessionID = nil
        }
        completionQueue.removeAll()
        notificationDismissWorkItem?.cancel()
        notificationDismissWorkItem = nil
        dismissNotificationOnHoverExit = false
    }

    func updateDisplays(_ displays: [DisplayDescriptor]) {
        let values = displays.map {
            AgentDisplayOption(id: $0.uuid,
                               title: $0.localizedName,
                               isNotched: $0.hasCameraHousing)
        }
        if values != displayOptions { displayOptions = values }
    }

    func reportResponseSuccess() {
        responseStatus = "Response sent".loc
    }

    func reportResponseFailure() {
        responseStatus = "The response could not be delivered. The request may have expired.".loc
    }

    func reportFollowUpResult(_ succeeded: Bool) {
        responseStatus = succeeded
            ? "Follow-up sent".loc
            : "The follow-up could not be delivered to the tmux session.".loc
    }
}

enum AgentSurfaceDiagnosticEvent: String, CaseIterable, Codable {
    case snapshotComposition
    case desktopShow
    case desktopHide
    case revealShow
    case revealHide
    case dwellCompleted
    case transition
}

struct AgentSurfaceDiagnosticsSnapshot: Codable, Equatable {
    let counters: [String: Int]
    let activeGlobalMonitors: Int
    let activeRetryTasks: Int
    let desktopPanelCreated: Int
    let revealPanelCreated: Int
}

enum AgentSurfaceDiagnostics {
    private static let lock = NSLock()
    private static var counters: [AgentSurfaceDiagnosticEvent: Int] = [:]
    private static var activeGlobalMonitors = 0
    private static var activeRetryTasks = 0
    private static var desktopPanelCreated = 0
    private static var revealPanelCreated = 0

    static func event(_ event: AgentSurfaceDiagnosticEvent) {
        lock.lock()
        counters[event, default: 0] += 1
        lock.unlock()
    }

    static func setActiveGlobalMonitors(_ count: Int) {
        lock.lock(); activeGlobalMonitors = max(count, 0); lock.unlock()
    }

    static func setActiveRetryTasks(_ count: Int) {
        lock.lock(); activeRetryTasks = max(count, 0); lock.unlock()
    }

    static func panelCreated(reveal: Bool) {
        lock.lock()
        if reveal { revealPanelCreated += 1 } else { desktopPanelCreated += 1 }
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        counters.removeAll(keepingCapacity: true)
        activeGlobalMonitors = 0
        activeRetryTasks = 0
        desktopPanelCreated = 0
        revealPanelCreated = 0
        lock.unlock()
    }

    static func snapshot() -> AgentSurfaceDiagnosticsSnapshot {
        lock.lock()
        let value = AgentSurfaceDiagnosticsSnapshot(
            counters: Dictionary(uniqueKeysWithValues: counters.map { ($0.key.rawValue, $0.value) }),
            activeGlobalMonitors: activeGlobalMonitors,
            activeRetryTasks: activeRetryTasks,
            desktopPanelCreated: desktopPanelCreated,
            revealPanelCreated: revealPanelCreated
        )
        lock.unlock()
        return value
    }
}

@MainActor
final class AgentSurfaceCoordinator {
    static let retryDelays: [TimeInterval] = [0, 0.08, 0.18, 0.35, 0.70, 1.20]
    static let topEdgeDwell: TimeInterval = 0.18
    static let ordinarySettleDelay: TimeInterval = 0.18

    let model: AgentSurfaceModel
    private let pingSessionMonitor = SessionMonitor()

    private weak var agentCoordinator: AgentSessionCoordinator?
    private let preferences: AppSettings
    private let evidenceSampler: FullscreenEvidenceSampler
    private let onOpenAgentCenter: () -> Void
    private let evidenceQueue = DispatchQueue(
        label: "com.n1ko.state.agent-surface-evidence",
        qos: .userInitiated
    )
    private var machine = FullscreenEnvironmentStateMachine()
    private(set) var desktopPanel: DesktopIslandPanel?
    private(set) var revealPanel: FullscreenRevealPanel?
    private var detachedWindowController: DetachedIslandWindowController?
    private var activeDetachmentPayload: IslandDetachmentPayload?
    private var desktopNotchViewModel: NotchViewModel?
    private var revealNotchViewModel: NotchViewModel?
    private var isDetached = false
    private var targetDisplay: DisplayDescriptor?
    private var notificationTokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var preferenceCancellables: Set<AnyCancellable> = []
    private var pointerLocalMonitor: Any?
    private var pointerGlobalMonitor: Any?
    private var escapeLocalMonitor: Any?
    private var desktopClickLocalMonitor: Any?
    private var desktopClickGlobalMonitor: Any?
    private var desktopKeyLocalMonitor: Any?
    private var desktopHoverLocalMonitor: Any?
    private var desktopHoverGlobalMonitor: Any?
    private var desktopHoverOpenWorkItem: DispatchWorkItem?
    private var desktopHoverCollapseWorkItem: DispatchWorkItem?
    private var dwellWorkItem: DispatchWorkItem?
    private var retryWorkItems: [UUID: DispatchWorkItem] = [:]
    private var transitionGeneration: UInt64 = 0
    private var reconciliationStartedAt: UInt64 = 0
    private var lastLoggedPhase: FullscreenEnvironmentPhase = .desktop
    private var installed = false

    init(agentCoordinator: AgentSessionCoordinator?,
         preferences: AppSettings = .shared,
         evidenceSampler: FullscreenEvidenceSampler = FullscreenEvidenceSampler(),
         onOpenAgentCenter: @escaping () -> Void) {
        self.agentCoordinator = agentCoordinator
        self.preferences = preferences
        self.evidenceSampler = evidenceSampler
        self.onOpenAgentCenter = onOpenAgentCenter
        model = AgentSurfaceModel(snapshot: agentCoordinator?.snapshot ?? .empty)
        pingSessionMonitor.configure(coordinator: agentCoordinator)
    }

    func install() {
        guard !installed else { return }
        installed = true
        isDetached = preferences.surfaceMode == .floatingPet
        installNotifications()
        installPreferenceObservation()
        agentCoordinator?.setSnapshotHandler { [weak self] snapshot in
            DispatchQueue.main.async {
                self?.consume(snapshot)
            }
        }
        updateDisplayCatalog()
        reconcile(reason: "install")
    }

    func shutdown() {
        installed = false
        transitionGeneration &+= 1
        agentCoordinator?.setSnapshotHandler(nil)
        pingSessionMonitor.configure(coordinator: nil)
        cancelRetryTasks()
        cancelDwell()
        stopPointerMonitoring()
        stopDesktopClickMonitoring()
        stopDesktopHoverMonitoring()
        cancelDesktopHoverTasks()
        notificationTokens.forEach { $0.center.removeObserver($0.token) }
        notificationTokens.removeAll()
        preferenceCancellables.removeAll()
        orderOutDesktop()
        orderOutReveal()
        orderOutDetached()
        desktopPanel?.contentViewController = nil
        revealPanel?.contentViewController = nil
        detachedWindowController?.dismiss()
        desktopPanel = nil
        revealPanel = nil
        detachedWindowController = nil
        activeDetachmentPayload = nil
        desktopNotchViewModel = nil
        revealNotchViewModel = nil
        isDetached = false
    }

    func suspend(reason: String) {
        machine.suspend()
        transitionGeneration &+= 1
        cancelRetryTasks()
        cancelDwell()
        stopPointerMonitoring()
        stopDesktopClickMonitoring()
        stopDesktopHoverMonitoring()
        cancelDesktopHoverTasks()
        orderOutDesktop()
        orderOutReveal()
        orderOutDetached()
        logTransition(reason: reason, evidence: nil)
    }

    func resume(reason: String) {
        machine.resume()
        orderOutDesktop()
        orderOutReveal()
        orderOutDetached()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.reconcile(reason: reason)
        }
    }

    func reconcile(reason: String, activeSpaceChanged: Bool = false) {
        guard installed else { return }
        if activeSpaceChanged { evidenceSampler.noteActiveSpaceChange() }
        transitionGeneration &+= 1
        let generation = transitionGeneration
        reconciliationStartedAt = DispatchTime.now().uptimeNanoseconds
        cancelRetryTasks()
        cancelDwell()
        orderOutReveal()
        machine.beginReconciliation()
        applyPhasePolicy()
        logTransition(reason: reason, evidence: nil)

        for delay in Self.retryDelays {
            let sampler = evidenceSampler
            let identifier = UUID()
            let item = DispatchWorkItem { [weak self] in
                guard let self, generation == self.transitionGeneration else { return }
                guard let display = self.targetDisplay else {
                    self.retryWorkItems.removeValue(forKey: identifier)
                    AgentSurfaceDiagnostics.setActiveRetryTasks(self.retryWorkItems.count)
                    return
                }
                self.evidenceQueue.async { [weak self] in
                    guard let self else { return }
                    let evidence = sampler.sample(display: display)
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.retryWorkItems.removeValue(forKey: identifier)
                        AgentSurfaceDiagnostics.setActiveRetryTasks(self.retryWorkItems.count)
                        guard generation == self.transitionGeneration else { return }
                        self.apply(evidence: evidence, reason: reason, delay: delay)
                    }
                }
            }
            retryWorkItems[identifier] = item
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }
        AgentSurfaceDiagnostics.setActiveRetryTasks(retryWorkItems.count)
    }

    func handlePointerForTesting(at point: NSPoint) {
        handlePointer(at: point)
    }

    var pingSessionsForTesting: [SessionState] { pingSessionMonitor.instances }
    var isDetachedForTesting: Bool { isDetached }
    var detachedWindowForTesting: NSWindow? { detachedWindowController?.window }

    var preparedDesktopContentViewControllerForTesting: NSViewController? {
        prepareDesktopPanel().contentViewController
    }

    var preparedDetachedWindowForTesting: NSWindow? {
        prepareDetachedController().window
    }

    func beginDetachmentForTesting(at point: CGPoint) {
        beginDetachment(from: IslandDetachmentRequest(
            source: .closed,
            dragStartScreenLocation: point,
            currentScreenLocation: point
        ))
    }

    func reattachForTesting() {
        reattachIsland()
    }

    var phaseForTesting: FullscreenEnvironmentPhase { machine.phase }

    func forceFullscreenForTesting(_ kind: FullscreenKind, display: DisplayDescriptor) {
        targetDisplay = display
        machine.beginReconciliation()
        let classification: FullscreenClassification = kind == .native
            ? .nativeFullscreen
            : .pseudoFullscreen
        let evidence = FullscreenEvidence(
            classification: classification,
            coverage: 1,
            ownerPID: nil,
            sampledAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds
        )
        _ = machine.consume(evidence)
        _ = machine.consume(evidence)
        applyPhasePolicy()
    }

    @discardableResult
    func completeTopEdgeDwellForTesting() -> Bool {
        let allowed = machine.beginReveal()
        if allowed {
            AgentSurfaceDiagnostics.event(.dwellCompleted)
            applyPhasePolicy()
        }
        return allowed
    }

    func routeResponseForTesting(_ request: AgentSurfaceResponseRequest) {
        routeResponse(request)
    }

    func dismissReveal(reason: String) {
        let wasVisible = revealPanel?.isVisible == true
        cancelDwell()
        orderOutReveal()
        machine.dismissReveal()
        if wasVisible { logTransition(reason: reason, evidence: nil) }
        applyPhasePolicy()
    }

    private func consume(_ snapshot: AgentSnapshot) {
        guard model.consume(snapshot) else { return }
        applyPhasePolicy()
    }

    private func installNotifications() {
        let workspace = NSWorkspace.shared.notificationCenter
        let activeSpace = workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconcile(reason: "active-space", activeSpaceChanged: true) }
        }
        notificationTokens.append((workspace, activeSpace))
        let activation = workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reconcile(reason: "frontmost-application") }
        }
        notificationTokens.append((workspace, activation))
        let systemSleep = workspace.addObserver(forName: NSWorkspace.willSleepNotification,
                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend(reason: "system-sleep") }
        }
        notificationTokens.append((workspace, systemSleep))
        let screenSleep = workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend(reason: "screen-sleep") }
        }
        notificationTokens.append((workspace, screenSleep))
        let sessionResign = workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                                  object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend(reason: "session-resign") }
        }
        notificationTokens.append((workspace, sessionResign))
        let systemWake = workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resume(reason: "system-wake") }
        }
        notificationTokens.append((workspace, systemWake))
        let screenWake = workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resume(reason: "screen-wake") }
        }
        notificationTokens.append((workspace, screenWake))
        let sessionActive = workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                                                  object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resume(reason: "session-active") }
        }
        notificationTokens.append((workspace, sessionActive))

        let screenToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateDisplayCatalog()
                self?.reconcile(reason: "screen-parameters")
            }
        }
        notificationTokens.append((NotificationCenter.default, screenToken))
    }

    private func installPreferenceObservation() {
        let publishers: [AnyPublisher<Void, Never>] = [
            preferences.$agentBehaviorEnabled.map { _ in () }.eraseToAnyPublisher(),
            preferences.$agentPresentationEnabled.map { _ in () }.eraseToAnyPublisher(),
            preferences.$agentFullscreenRevealEnabled.map { _ in () }.eraseToAnyPublisher(),
            preferences.$agentTargetDisplayUUID.map { _ in () }.eraseToAnyPublisher(),
            preferences.$surfaceMode.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(publishers)
            .dropFirst(publishers.count)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.synchronizeSurfaceMode()
                self?.updateDisplayCatalog()
                self?.reconcile(reason: "preference")
            }
            .store(in: &preferenceCancellables)

        model.$isExpanded
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.positionVisiblePanels()
                self?.updateDesktopClickMonitoring()
                self?.updateDesktopHoverMonitoring()
            }
            .store(in: &preferenceCancellables)

        model.$expansionTrigger
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.positionVisiblePanels()
                self?.updateDesktopClickMonitoring()
                self?.updateDesktopHoverMonitoring()
            }
            .store(in: &preferenceCancellables)

        model.$openedMeasuredContentHeight
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.positionVisiblePanels()
            }
            .store(in: &preferenceCancellables)
    }

    private func synchronizeSurfaceMode() {
        let shouldDetach = preferences.surfaceMode == .floatingPet
        guard shouldDetach != isDetached else { return }

        isDetached = shouldDetach
        activeDetachmentPayload = nil
        model.collapse()
        if shouldDetach {
            orderOutDesktop()
        } else {
            detachedWindowController?.dismiss()
            detachedWindowController = nil
            desktopNotchViewModel?.redockAfterDetached()
        }
        applyPhasePolicy()
    }

    private func updateDisplayCatalog() {
        let displays = DisplayCatalog.current()
        model.updateDisplays(displays)
        targetDisplay = DisplayCatalog.target(
            preferredUUID: preferences.agentTargetDisplayUUID,
            pointer: NSEvent.mouseLocation,
            displays: displays
        )
        if preferences.agentTargetDisplayUUID != AppSettings.automaticDisplaySelection,
           !displays.contains(where: { $0.uuid == preferences.agentTargetDisplayUUID }) {
            preferences.agentTargetDisplayUUID = AppSettings.automaticDisplaySelection
            targetDisplay = DisplayCatalog.target(
                preferredUUID: AppSettings.automaticDisplaySelection,
                pointer: NSEvent.mouseLocation,
                displays: displays
            )
        }
        let selectedScreen = targetDisplay.flatMap { display in
            NSScreen.screens.first {
                DisplayCatalog.descriptor(for: $0)?.displayID == display.displayID
            }
        }
        ScreenSelector.shared.projectN1KOTarget(selectedScreen)
        updatePingScreenGeometry()
    }

    private func apply(evidence: FullscreenEvidence, reason: String, delay: TimeInterval) {
        _ = machine.consume(evidence)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - reconciliationStartedAt) / 1_000_000_000
        let ordinaryStillSettling = machine.phase == .desktop && elapsed < Self.ordinarySettleDelay
        if !ordinaryStillSettling { applyPhasePolicy() }
        logTransition(reason: "\(reason)@\(Int((delay * 1_000).rounded()))ms", evidence: evidence)
    }

    private var presentationAllowed: Bool {
        preferences.agentBehaviorEnabled
            && preferences.agentPresentationEnabled
    }

    private func applyPhasePolicy() {
        switch machine.phase {
        case .desktop:
            stopPointerMonitoring()
            orderOutReveal()
            if presentationAllowed {
                if isDetached {
                    orderOutDesktop()
                    showDetached()
                } else {
                    orderOutDetached()
                    showDesktop()
                }
            } else {
                orderOutDesktop()
                orderOutDetached()
            }
        case .entering, .exiting:
            orderOutDesktop()
            orderOutReveal()
            orderOutDetached()
            if preferences.agentFullscreenRevealEnabled && presentationAllowed {
                startPointerMonitoring()
            } else {
                stopPointerMonitoring()
            }
        case .fullscreen:
            orderOutDesktop()
            orderOutReveal()
            orderOutDetached()
            if preferences.agentFullscreenRevealEnabled && presentationAllowed {
                startPointerMonitoring()
            } else {
                stopPointerMonitoring()
            }
        case .revealing:
            orderOutDesktop()
            orderOutDetached()
            if preferences.agentFullscreenRevealEnabled && presentationAllowed {
                startPointerMonitoring()
                showReveal()
            } else {
                dismissReveal(reason: "presentation-disabled")
            }
        case .suspended:
            stopPointerMonitoring()
            orderOutDesktop()
            orderOutReveal()
            orderOutDetached()
        }
    }

    private func prepareDesktopPanel() -> DesktopIslandPanel {
        if let desktopPanel { return desktopPanel }
        let panel = DesktopIslandPanel()
        AgentSurfaceDiagnostics.panelCreated(reveal: false)
        let viewModel = pingViewModel(reveal: false)
        panel.onCancel = { [weak viewModel] in
            Task { @MainActor in viewModel?.notchClose() }
        }
        panel.contentViewController = NotchViewController(
            viewModel: viewModel,
            sessionMonitor: pingSessionMonitor
        )
        bindMousePresentation(panel: panel, viewModel: viewModel)
        desktopPanel = panel
        return panel
    }

    private func prepareRevealPanel() -> FullscreenRevealPanel {
        if let revealPanel { return revealPanel }
        let panel = FullscreenRevealPanel()
        AgentSurfaceDiagnostics.panelCreated(reveal: true)
        panel.onCancel = { [weak self] in self?.dismissReveal(reason: "escape") }
        let viewModel = pingViewModel(reveal: true)
        panel.contentViewController = NotchViewController(
            viewModel: viewModel,
            sessionMonitor: pingSessionMonitor
        )
        bindMousePresentation(panel: panel, viewModel: viewModel)
        revealPanel = panel
        return panel
    }

    private func bindMousePresentation(
        panel: AgentInteractivePanel,
        viewModel: NotchViewModel
    ) {
        panel.ignoresMouseEvents = viewModel.status != .opened
        viewModel.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak panel, weak viewModel] status in
                guard let panel else { return }
                panel.ignoresMouseEvents = status != .opened
                if status == .opened, viewModel?.openReason != .notification {
                    panel.makeKey()
                }
            }
            .store(in: &preferenceCancellables)
    }

    private func prepareDetachedController() -> DetachedIslandWindowController {
        if let detachedWindowController { return detachedWindowController }
        let viewModel = pingViewModel(reveal: false)
        let controller = DetachedIslandWindowController(
            viewModel: viewModel,
            sessionMonitor: pingSessionMonitor,
            onClose: { [weak self] in self?.reattachIsland() },
            onPetAnchorChanged: { [weak self] anchor in
                self?.persistFloatingPetAnchor(anchor)
            }
        )
        controller.onRedockRequested = { [weak self] in self?.reattachIsland() }
        detachedWindowController = controller
        return controller
    }

    private func showDesktop() {
        guard let targetDisplay, !isDetached else { return }
        let panel = prepareDesktopPanel()
        setFrame(for: panel, on: targetDisplay, reveal: false)
        if !panel.isVisible {
            panel.orderFrontRegardless()
            AgentSurfaceDiagnostics.event(.desktopShow)
        }
        updateDesktopClickMonitoring()
        updateDesktopHoverMonitoring()
    }

    private func orderOutDesktop() {
        guard let panel = desktopPanel, panel.isVisible else { return }
        panel.orderOut(nil)
        AgentSurfaceDiagnostics.event(.desktopHide)
        stopDesktopClickMonitoring()
        stopDesktopHoverMonitoring()
        cancelDesktopHoverTasks()
    }

    private func showReveal() {
        guard let targetDisplay else { return }
        let panel = prepareRevealPanel()
        revealNotchViewModel?.notchOpen(reason: .hover)
        setFrame(for: panel, on: targetDisplay, reveal: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
            AgentSurfaceDiagnostics.event(.revealShow)
        }
    }

    private func orderOutReveal() {
        guard let panel = revealPanel, panel.isVisible else { return }
        panel.orderOut(nil)
        revealNotchViewModel?.notchClose()
        AgentSurfaceDiagnostics.event(.revealHide)
    }

    private func showDetached() {
        guard isDetached else { return }
        let controller = prepareDetachedController()
        guard controller.window?.isVisible != true else { return }
        let anchor = controller.currentPetAnchor ?? resolvedFloatingPetAnchor()
        controller.present(
            atPetAnchor: anchor,
            activatesApplication: false,
            presentsAutomaticContent: false
        )
        controller.activateInteraction()
    }

    private func orderOutDetached() {
        detachedWindowController?.dismiss()
    }

    private func reattachIsland() {
        isDetached = false
        activeDetachmentPayload = nil
        detachedWindowController?.dismiss()
        detachedWindowController = nil
        desktopNotchViewModel?.redockAfterDetached()
        preferences.surfaceMode = .notch
        model.collapse()
        applyPhasePolicy()
    }

    private func beginDetachment(from request: IslandDetachmentRequest) {
        guard machine.phase == .desktop, presentationAllowed else { return }
        let viewModel = pingViewModel(reveal: false)
        let content = IslandDetachedContentResolver.resolve(
            status: viewModel.status,
            openReason: viewModel.openReason,
            contentType: viewModel.contentType,
            sessions: pingSessionMonitor.instances
        )
        viewModel.beginDetachedPresentation(contentType: content, playSound: true)
        let size = DetachedIslandWindowController.windowSize(
            for: viewModel,
            sessionMonitor: pingSessionMonitor
        )
        let cursorWindowOffset = CGPoint(
            x: size.width / 2,
            y: max(viewModel.closedHeight + 18, size.height - 24)
        )
        activeDetachmentPayload = IslandDetachmentPayload(
            contentType: content,
            dragStartScreenLocation: request.dragStartScreenLocation,
            initialCursorScreenLocation: request.currentScreenLocation,
            cursorWindowOffset: cursorWindowOffset
        )
        isDetached = true
        preferences.surfaceMode = .floatingPet
        model.collapse()
        orderOutDesktop()
        let origin = DetachedIslandWindowController.windowOrigin(
            for: request.currentScreenLocation,
            cursorWindowOffset: cursorWindowOffset,
            windowSize: size
        )
        prepareDetachedController().present(at: origin)
    }

    private func updateDetachment(cursorLocation: CGPoint) {
        guard let payload = activeDetachmentPayload else { return }
        detachedWindowController?.updateDragPosition(
            cursorLocation: cursorLocation,
            cursorWindowOffset: payload.cursorWindowOffset
        )
    }

    private func finishDetachment(cursorLocation: CGPoint?) {
        if let cursorLocation { updateDetachment(cursorLocation: cursorLocation) }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.detachedWindowController?.endWindowDrag()
            if let anchor = self.detachedWindowController?.currentPetAnchor {
                self.persistFloatingPetAnchor(anchor)
            }
        }
    }

    private func resolvedFloatingPetAnchor() -> CGPoint {
        let point = detachedWindowController?.currentPetAnchor ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? targetDisplay?.appKitFrame ?? .zero
        return DetachedIslandWindowController.petAnchor(
            from: preferences.floatingPetAnchor,
            in: visibleFrame,
            defaultWindowFrame: nil
        )
    }

    private func persistFloatingPetAnchor(_ anchor: CGPoint) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        preferences.floatingPetAnchor = DetachedIslandWindowController.floatingPetAnchor(
            from: anchor,
            in: visibleFrame
        )
    }

    private func positionVisiblePanels() {
        guard let targetDisplay else { return }
        if let desktopPanel, desktopPanel.isVisible {
            setFrame(for: desktopPanel, on: targetDisplay, reveal: false)
        }
        if let revealPanel, revealPanel.isVisible {
            setFrame(for: revealPanel, on: targetDisplay, reveal: true)
        }
    }

    private func updateDesktopClickMonitoring() {
        let shouldMonitor = desktopPanel?.isVisible == true
            && model.isExpanded
            && model.expansionTrigger != .hover
        if shouldMonitor {
            startDesktopClickMonitoring()
        } else {
            stopDesktopClickMonitoring()
        }
    }

    private func startDesktopClickMonitoring() {
        guard desktopClickLocalMonitor == nil,
              desktopClickGlobalMonitor == nil,
              desktopKeyLocalMonitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        desktopClickLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: events) {
            [weak self] event in
            self?.handleDesktopClick(at: NSEvent.mouseLocation)
            return event
        }
        desktopClickGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) {
            [weak self] _ in
            DispatchQueue.main.async { self?.handleDesktopClick(at: NSEvent.mouseLocation) }
        }
        desktopKeyLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {
                self.model.collapse()
                return nil
            }
            guard self.model.route(for: .desktop) == .sessionList else { return event }
            switch event.keyCode {
            case 125:
                self.model.moveSelection(1)
                return nil
            case 126:
                self.model.moveSelection(-1)
                return nil
            case 36, 76:
                if let session = self.model.selectedSession() {
                    self.handleSessionAction(.focus(session))
                    self.model.collapse()
                }
                return nil
            default:
                return event
            }
        }
        refreshGlobalMonitorDiagnostics()
    }

    private func stopDesktopClickMonitoring() {
        [desktopClickLocalMonitor, desktopClickGlobalMonitor, desktopKeyLocalMonitor].compactMap { $0 }.forEach {
            NSEvent.removeMonitor($0)
        }
        desktopClickLocalMonitor = nil
        desktopClickGlobalMonitor = nil
        desktopKeyLocalMonitor = nil
        refreshGlobalMonitorDiagnostics()
    }

    private func handleDesktopClick(at point: NSPoint) {
        guard let panel = desktopPanel,
              panel.isVisible,
              model.expansionTrigger != .hover,
              !panel.frame.contains(point) else { return }
        model.collapse()
    }

    private func handleDesktopIslandHover(_ hovering: Bool) {
        desktopHoverOpenWorkItem?.cancel()
        desktopHoverOpenWorkItem = nil
        desktopHoverCollapseWorkItem?.cancel()
        desktopHoverCollapseWorkItem = nil

        if hovering {
            guard !model.isExpanded else { return }
            let item = DispatchWorkItem { [weak self] in
                guard let self,
                      let panel = self.desktopPanel,
                      panel.isVisible,
                      panel.frame.insetBy(dx: -10, dy: -6).contains(NSEvent.mouseLocation),
                      !self.model.isExpanded else { return }
                self.model.expand(reason: .hover)
            }
            desktopHoverOpenWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + AgentIslandLayout.hoverActivationDelay,
                                          execute: item)
            return
        }

        guard model.expansionTrigger == .hover else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self, let panel = self.desktopPanel else { return }
            if !panel.frame.insetBy(dx: -10, dy: -10).contains(NSEvent.mouseLocation) {
                self.model.collapse()
            }
        }
        desktopHoverCollapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    private func updateDesktopHoverMonitoring() {
        let shouldMonitor = desktopPanel?.isVisible == true
            && model.isExpanded
            && model.expansionTrigger == .hover
        if shouldMonitor {
            startDesktopHoverMonitoring()
        } else {
            stopDesktopHoverMonitoring()
        }
    }

    private func startDesktopHoverMonitoring() {
        guard desktopHoverLocalMonitor == nil, desktopHoverGlobalMonitor == nil else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        desktopHoverLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: events) {
            [weak self] event in
            self?.handleDesktopHoverPointer(at: NSEvent.mouseLocation)
            return event
        }
        desktopHoverGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) {
            [weak self] _ in
            DispatchQueue.main.async { self?.handleDesktopHoverPointer(at: NSEvent.mouseLocation) }
        }
        refreshGlobalMonitorDiagnostics()
    }

    private func stopDesktopHoverMonitoring() {
        [desktopHoverLocalMonitor, desktopHoverGlobalMonitor].compactMap { $0 }.forEach {
            NSEvent.removeMonitor($0)
        }
        desktopHoverLocalMonitor = nil
        desktopHoverGlobalMonitor = nil
        refreshGlobalMonitorDiagnostics()
    }

    private func cancelDesktopHoverTasks() {
        desktopHoverOpenWorkItem?.cancel()
        desktopHoverOpenWorkItem = nil
        desktopHoverCollapseWorkItem?.cancel()
        desktopHoverCollapseWorkItem = nil
    }

    private func handleDesktopHoverPointer(at point: NSPoint) {
        guard model.expansionTrigger == .hover,
              let panel = desktopPanel,
              panel.isVisible else { return }
        if !panel.frame.insetBy(dx: -10, dy: -10).contains(point) {
            model.collapse()
        }
    }

    private func setFrame(for panel: NSPanel, on display: DisplayDescriptor, reveal: Bool) {
        let windowHeight = min(CGFloat(750), display.appKitFrame.height)
        let frame = CGRect(
            x: display.appKitFrame.minX,
            y: display.appKitFrame.maxY - windowHeight,
            width: display.appKitFrame.width,
            height: windowHeight
        )
        guard panel.frame != frame else { return }
        guard panel.isVisible, !Theme.reduceMotion else {
            panel.setFrame(frame, display: panel.isVisible, animate: false)
            return
        }
        panel.setFrame(frame, display: true, animate: true)
    }

    private func pingViewModel(reveal: Bool) -> NotchViewModel {
        if reveal, let revealNotchViewModel { return revealNotchViewModel }
        if !reveal, let desktopNotchViewModel { return desktopNotchViewModel }

        let display = targetDisplay
            ?? DisplayCatalog.target(
                preferredUUID: preferences.agentTargetDisplayUUID,
                pointer: NSEvent.mouseLocation
            )
            ?? DisplayCatalog.current().first!
        let geometry = pingGeometry(for: display)
        let viewModel = NotchViewModel(
            deviceNotchRect: geometry.deviceNotchRect,
            screenRect: display.appKitFrame,
            windowHeight: geometry.windowHeight,
            hasPhysicalNotch: geometry.hasPhysicalNotch,
            enableEventMonitoring: !reveal,
            observeSystemEnvironment: false,
            fullscreenActivityProvider: { _ in false },
            hideInFullscreenProvider: { false },
            fullscreenBrowserHiddenProvider: { _ in false },
            autoHideWhenIdleProvider: { AppSettings.shared.autoHideWhenIdle },
            notchModuleWidthProvider: { AppSettings.shared.notchModuleWidth }
        )
        if reveal {
            revealNotchViewModel = viewModel
        } else {
            desktopNotchViewModel = viewModel
            viewModel.onDetachmentRequested = { [weak self] request in
                self?.beginDetachment(from: request)
            }
            viewModel.onDetachmentUpdated = { [weak self] location in
                self?.updateDetachment(cursorLocation: location)
            }
            viewModel.onDetachmentFinished = { [weak self] location in
                self?.finishDetachment(cursorLocation: location)
            }
        }
        return viewModel
    }

    private func updatePingScreenGeometry() {
        guard let targetDisplay else { return }
        let geometry = pingGeometry(for: targetDisplay)
        [desktopNotchViewModel, revealNotchViewModel].compactMap { $0 }.forEach {
            $0.updateScreenGeometry(
                deviceNotchRect: geometry.deviceNotchRect,
                screenRect: targetDisplay.appKitFrame,
                windowHeight: geometry.windowHeight,
                hasPhysicalNotch: geometry.hasPhysicalNotch
            )
        }
    }

    private func pingGeometry(for display: DisplayDescriptor) -> (
        deviceNotchRect: CGRect,
        windowHeight: CGFloat,
        hasPhysicalNotch: Bool
    ) {
        let screen = NSScreen.screens.first {
            DisplayCatalog.descriptor(for: $0)?.displayID == display.displayID
        }
        let metrics = screen?.notchMetrics ?? ScreenNotchMetrics.detect(
            screenFrame: display.appKitFrame,
            safeAreaTop: display.safeAreaTop,
            auxiliaryTopLeftWidth: nil,
            auxiliaryTopRightWidth: nil
        )
        let windowHeight = min(CGFloat(750), display.appKitFrame.height)
        return (
            CGRect(
                x: (display.appKitFrame.width - metrics.size.width) / 2,
                y: 0,
                width: metrics.size.width,
                height: metrics.size.height
            ),
            windowHeight,
            metrics.hasPhysicalNotch
        )
    }

    private func startPointerMonitoring() {
        guard pointerGlobalMonitor == nil, pointerLocalMonitor == nil else { return }
        pointerLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) {
            [weak self] event in
            self?.handlePointer(at: NSEvent.mouseLocation)
            return event
        }
        pointerGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) {
            [weak self] _ in
            DispatchQueue.main.async { self?.handlePointer(at: NSEvent.mouseLocation) }
        }
        escapeLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.revealPanel?.isVisible == true {
                self?.dismissReveal(reason: "escape")
                return nil
            }
            return event
        }
        refreshGlobalMonitorDiagnostics()
    }

    private func stopPointerMonitoring() {
        [pointerLocalMonitor, pointerGlobalMonitor, escapeLocalMonitor].compactMap { $0 }.forEach {
            NSEvent.removeMonitor($0)
        }
        pointerLocalMonitor = nil
        pointerGlobalMonitor = nil
        escapeLocalMonitor = nil
        refreshGlobalMonitorDiagnostics()
        cancelDwell()
    }

    private func refreshGlobalMonitorDiagnostics() {
        let count = [pointerGlobalMonitor, desktopClickGlobalMonitor, desktopHoverGlobalMonitor]
            .compactMap { $0 }
            .count
        AgentSurfaceDiagnostics.setActiveGlobalMonitors(count)
    }

    private func handlePointer(at point: NSPoint) {
        guard let targetDisplay else { return }
        let trigger = DisplayCoordinateNormalizer.topEdgeTriggerRect(on: targetDisplay)
        if revealPanel?.isVisible == true {
            let islandRegion: CGRect
            if let viewModel = revealNotchViewModel {
                islandRegion = viewModel.status == .opened
                    ? viewModel.geometry.openedScreenRect(for: viewModel.openedSize)
                        .insetBy(dx: -10, dy: -10)
                    : viewModel.closedScreenRect.insetBy(dx: -10, dy: -5)
            } else {
                islandRegion = .zero
            }
            if !islandRegion.contains(point) && !trigger.contains(point) {
                dismissReveal(reason: "pointer-exit")
            }
            return
        }

        guard machine.phase.stableFullscreenKind != nil,
              presentationAllowed,
              preferences.agentFullscreenRevealEnabled,
              trigger.contains(point) else {
            cancelDwell()
            return
        }
        beginDwell()
    }

    private func beginDwell() {
        guard dwellWorkItem == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.dwellWorkItem = nil
            guard let targetDisplay = self.targetDisplay,
                  DisplayCoordinateNormalizer.topEdgeTriggerRect(on: targetDisplay)
                    .contains(NSEvent.mouseLocation),
                  self.presentationAllowed,
                  self.preferences.agentFullscreenRevealEnabled,
                  self.machine.beginReveal() else { return }
            AgentSurfaceDiagnostics.event(.dwellCompleted)
            self.applyPhasePolicy()
            self.logTransition(reason: "top-edge-dwell", evidence: nil)
        }
        dwellWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.topEdgeDwell, execute: item)
    }

    private func cancelDwell() {
        dwellWorkItem?.cancel()
        dwellWorkItem = nil
    }

    private func cancelRetryTasks() {
        retryWorkItems.values.forEach { $0.cancel() }
        retryWorkItems.removeAll()
        AgentSurfaceDiagnostics.setActiveRetryTasks(0)
    }

    private func routeResponse(_ request: AgentSurfaceResponseRequest) {
        do {
            try agentCoordinator?.respond(
                provider: request.provider,
                sessionID: request.sessionID,
                requestID: request.requestID,
                ownerID: request.ownerID,
                capability: request.capability,
                action: request.action
            )
            guard agentCoordinator != nil else { throw AgentResponseRoutingError.channelClosed }
            model.reportResponseSuccess()
        } catch {
            model.reportResponseFailure()
        }
    }

    private func handleSessionAction(_ action: AgentSessionSurfaceAction) {
        switch action {
        case .focus(let session):
            AgentIntegrationController.shared.focus(session: session)
        case .archive(let session):
            _ = agentCoordinator?.archive(provider: session.provider, sessionID: session.sessionID)
            model.showSessionList()
        }
    }

    private func logTransition(reason: String, evidence: FullscreenEvidence?) {
        let phaseChanged = machine.phase != lastLoggedPhase
        guard phaseChanged || evidence != nil else { return }
        lastLoggedPhase = machine.phase
        AgentSurfaceDiagnostics.event(.transition)
        let display = targetDisplay?.uuid ?? "none"
        let classification = evidence?.classification.rawValue ?? "signal"
        let coverage = evidence.map { String(format: "%.4f", $0.coverage) } ?? "-"
        DiagLog.log(
            "AgentSurface",
            "transition reason=\(reason) phase=\(String(describing: machine.phase)) " +
            "classification=\(classification) coverage=\(coverage) display=\(display)"
        )
    }
}
