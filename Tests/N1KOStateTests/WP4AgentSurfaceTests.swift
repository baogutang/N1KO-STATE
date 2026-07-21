import AppKit
import CoreGraphics
import N1KOAgentCore
import N1KOWindowCore
import SwiftUI
import XCTest
@testable import N1KOState

@MainActor
final class WP4AgentSurfaceTests: XCTestCase {
    func testDesktopAndRevealPanelsHaveStructurallyDifferentFullscreenRoles() {
        AgentSurfaceDiagnostics.reset()
        let desktop = DesktopIslandPanel()
        let reveal = FullscreenRevealPanel()
        let detached = DetachedIslandPanel()
        defer {
            desktop.orderOut(nil)
            reveal.orderOut(nil)
            detached.orderOut(nil)
        }

        XCTAssertTrue(desktop.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertFalse(desktop.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(desktop.collectionBehavior.contains(.stationary))
        XCTAssertTrue(desktop.collectionBehavior.contains(.ignoresCycle))
        XCTAssertTrue(desktop.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(desktop.collectionBehavior.contains(.fullScreenAuxiliary))

        XCTAssertTrue(reveal.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(detached.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(detached.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(detached.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(reveal.isVisible)
        XCTAssertFalse(desktop.hasShadow)
        XCTAssertFalse(reveal.hasShadow)
        XCTAssertFalse(detached.hasShadow)
    }

    func testRuntimeHostsPinnedNotchAndDetachedControllers() throws {
        let surface = AgentSurfaceCoordinator(
            agentCoordinator: makeAgentCoordinator(),
            onOpenAgentCenter: {}
        )
        defer { surface.shutdown() }

        XCTAssertTrue(surface.preparedDesktopContentViewControllerForTesting is NotchViewController)
        let window = try XCTUnwrap(surface.preparedDetachedWindowForTesting)
        XCTAssertTrue(String(describing: type(of: window)).contains("DetachedIslandWindow"))
        XCTAssertTrue(String(describing: type(of: try XCTUnwrap(window.contentView)))
            .contains("TransparentHostingView"))
        XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(window.collectionBehavior.contains(.fullScreenAuxiliary))

        surface.shutdown()
        XCTAssertNil(surface.detachedWindowForTesting)
    }

    func testPinnedSourceNotchRendersCompactClickHoverAndRevealSurfaces() throws {
        let settings = AppSettings.shared
        let originalAutoHide = settings.autoHideWhenIdle
        let originalDisplayMode = settings.notchDisplayMode
        let originalSurfaceMode = settings.surfaceMode
        let originalHintPending = settings.notchDetachmentHintPending
        settings.autoHideWhenIdle = false
        settings.notchDisplayMode = .detailed
        settings.surfaceMode = .notch
        settings.notchDetachmentHintPending = false
        defer {
            settings.autoHideWhenIdle = originalAutoHide
            settings.notchDisplayMode = originalDisplayMode
            settings.surfaceMode = originalSurfaceMode
            settings.notchDetachmentHintPending = originalHintPending
        }

        let core = makeAgentCoordinator()
        _ = core.ingest(AgentIngressEvent(
            provider: .claude,
            sessionID: "source-claude",
            kind: .processing,
            cwd: "/tmp/N1KO-STATE",
            title: "Refine the Island",
            message: "Matching the pinned Ping-Island source"
        ))
        _ = core.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "source-codex",
            kind: .processing,
            cwd: "/tmp/N1KO-STATE",
            title: "Verify source parity",
            message: "Running the source-level controller checks",
            usage: AgentUsage(inputTokens: 8_400, cachedInputTokens: 2_100, outputTokens: 940),
            usageWindows: [
                AgentUsageWindow(key: "primary", label: "5h", usedPercentage: 22),
                AgentUsageWindow(key: "secondary", label: "7d", usedPercentage: 64)
            ]
        ))

        let monitor = SessionMonitor()
        monitor.configure(coordinator: core)
        spinRunLoop(seconds: 0.05)
        XCTAssertEqual(monitor.instances.count, 2)

        let viewModel = NotchViewModel(
            deviceNotchRect: .zero,
            screenRect: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            windowHeight: 520,
            hasPhysicalNotch: false,
            enableEventMonitoring: false,
            observeSystemEnvironment: false,
            fullscreenActivityProvider: { _ in false },
            hideInFullscreenProvider: { false },
            fullscreenBrowserHiddenProvider: { _ in false },
            autoHideWhenIdleProvider: { false },
            notchModuleWidthProvider: { 266 }
        )
        let root = ZStack(alignment: .top) {
            Color(white: 0.16)
            AppLocalizedRootView {
                NotchView(viewModel: viewModel, sessionMonitor: monitor)
            }
        }

        viewModel.notchClose()
        let compact = try XCTUnwrap(render(root, size: CGSize(width: 700, height: 120)))
        try captureIfRequested(compact, name: "ping-source-compact")

        viewModel.notchOpen(reason: .click)
        spinRunLoop(seconds: 0.03)
        let click = try XCTUnwrap(render(root, size: CGSize(width: 700, height: 520)))
        try captureIfRequested(click, name: "ping-source-click")

        viewModel.notchClose()
        viewModel.notchOpen(reason: .hover)
        spinRunLoop(seconds: 0.03)
        let hover = try XCTUnwrap(render(root, size: CGSize(width: 700, height: 420)))
        try captureIfRequested(hover, name: "ping-source-hover")
        try captureIfRequested(hover, name: "ping-source-fullscreen-reveal")

        monitor.configure(coordinator: nil)
    }

    func testN1KOSnapshotAdapterPreservesPingCompletionAndMascotSemantics() throws {
        let core = makeAgentCoordinator()
        let surface = AgentSurfaceCoordinator(agentCoordinator: core, onOpenAgentCenter: {})
        defer { surface.shutdown() }
        surface.install()

        let started = Date()
        _ = core.ingest(AgentIngressEvent(
            provider: .qwen,
            sessionID: "qwen-parity",
            kind: .processing,
            timestamp: started,
            message: "Working"
        ))
        _ = core.ingest(AgentIngressEvent(
            provider: .qwen,
            sessionID: "qwen-parity",
            kind: .completed,
            timestamp: started.addingTimeInterval(1),
            message: "Ready for review"
        ))
        _ = core.ingest(AgentIngressEvent(
            provider: .openClaw,
            sessionID: "openclaw-parity",
            kind: .processing,
            timestamp: started.addingTimeInterval(2),
            message: "Gateway working"
        ))
        _ = core.ingest(AgentIngressEvent(
            provider: .workBuddy,
            sessionID: "workbuddy-parity",
            kind: .processing,
            timestamp: started.addingTimeInterval(3),
            message: "IDE working"
        ))
        spinRunLoop(seconds: 0.05)

        let qwen = try XCTUnwrap(surface.pingSessionsForTesting.first {
            $0.sessionId == "qwen-parity"
        })
        XCTAssertEqual(qwen.phase, .waitingForInput)
        XCTAssertEqual(qwen.mascotClient, .qwen)
        XCTAssertTrue(SessionCompletionStateEvaluator.isCompletedReadySession(qwen))
        XCTAssertEqual(
            surface.pingSessionsForTesting.first { $0.sessionId == "openclaw-parity" }?.mascotClient,
            .openclaw
        )
        XCTAssertEqual(
            surface.pingSessionsForTesting.first { $0.sessionId == "workbuddy-parity" }?.mascotClient,
            .codebuddy
        )
        XCTAssertEqual(
            N1KOSessionActionRouter.shared.source(sessionID: "qwen-parity")?.provider,
            .qwen
        )
    }

    func testPingIslandParityGeometryIsTopAttachedAndTriggerSpecific() {
        let display = CGRect(x: 100, y: 200, width: 1512, height: 982)
        let empty = AgentSurfaceProjection.empty

        let compact = AgentIslandLayout.panelFrame(
            on: display,
            surface: .desktop,
            isExpanded: false,
            trigger: nil,
            projection: empty
        )
        XCTAssertEqual(compact.size, CGSize(width: 266, height: 32))
        XCTAssertEqual(compact.midX, display.midX, accuracy: 0.001)
        XCTAssertEqual(compact.maxY, display.maxY, accuracy: 0.001)

        let clicked = AgentIslandLayout.panelFrame(
            on: display,
            surface: .desktop,
            isExpanded: true,
            trigger: .click,
            projection: empty
        )
        let hovered = AgentIslandLayout.panelFrame(
            on: display,
            surface: .desktop,
            isExpanded: true,
            trigger: .hover,
            projection: empty
        )
        let reveal = AgentIslandLayout.panelFrame(
            on: display,
            surface: .fullscreenReveal,
            isExpanded: false,
            trigger: nil,
            projection: empty
        )
        XCTAssertEqual(clicked.width, 520)
        XCTAssertEqual(hovered.width, 600)
        XCTAssertEqual(reveal.width, 600)
        XCTAssertEqual(clicked.maxY, display.maxY, accuracy: 0.001)
        XCTAssertEqual(hovered.maxY, display.maxY, accuracy: 0.001)
        XCTAssertEqual(reveal.maxY, display.maxY, accuracy: 0.001)
        XCTAssertEqual(AgentIslandLayout.closedTopRadius, 6)
        XCTAssertEqual(AgentIslandLayout.closedBottomRadius, 14)
        XCTAssertEqual(AgentIslandLayout.openTopRadius, 19)
        XCTAssertEqual(AgentIslandLayout.openBottomRadius, 24)
        XCTAssertEqual(AgentIslandLayout.hoverActivationDelay, 0.24, accuracy: 0.001)

        let measured = AgentIslandLayout.size(
            surface: .desktop,
            isExpanded: true,
            trigger: .click,
            projection: empty,
            measuredContentHeight: 173.2
        )
        XCTAssertEqual(measured, CGSize(width: 520, height: 218))

        let conversation = AgentIslandLayout.size(
            surface: .desktop,
            isExpanded: true,
            trigger: .click,
            projection: empty,
            route: .conversation("session")
        )
        XCTAssertEqual(conversation, CGSize(width: 600, height: 580))

        let narrowDisplay = CGRect(x: 0, y: 0, width: 900, height: 560)
        let narrowClick = AgentIslandLayout.panelFrame(
            on: narrowDisplay,
            surface: .desktop,
            isExpanded: true,
            trigger: .click,
            projection: empty
        )
        let narrowConversation = AgentIslandLayout.panelFrame(
            on: narrowDisplay,
            surface: .desktop,
            isExpanded: true,
            trigger: .hover,
            projection: empty,
            route: .conversation("session")
        )
        XCTAssertEqual(narrowClick.width, 396)
        XCTAssertEqual(narrowConversation.width, 600)
        XCTAssertEqual(narrowConversation.height, 440)
    }

    func testPingIslandDetachmentGateMatchesPinnedGesture() {
        XCTAssertEqual(AgentIslandDetachmentGate.minimumPressDuration, 0.35, accuracy: 0.001)
        XCTAssertEqual(AgentIslandDetachmentGate.maximumPrepressMovement, 8)
        XCTAssertEqual(AgentIslandDetachmentGate.minimumDownwardTranslation, 20)
        XCTAssertTrue(AgentIslandDetachmentGate.accepts(CGSize(width: 2, height: 20)))
        XCTAssertFalse(AgentIslandDetachmentGate.accepts(CGSize(width: 1, height: 19.9)))
        XCTAssertFalse(AgentIslandDetachmentGate.accepts(CGSize(width: 24, height: 20)))
        XCTAssertFalse(AgentIslandDetachmentGate.accepts(CGSize(width: 0, height: -30)))
    }

    func testDetachedBubbleLayoutPreservesPinnedMetricsAndChoosesVisiblePlacement() {
        let bubble = CGSize(width: 392, height: 220)
        let topLeft = AgentDetachedIslandLayout.windowLayout(
            bubbleSize: bubble,
            placement: .topLeft
        )
        XCTAssertEqual(topLeft.containerSize, CGSize(width: 490, height: 250))
        XCTAssertEqual(topLeft.bubbleFrame, CGRect(x: 2, y: 2, width: 392, height: 220))
        XCTAssertEqual(topLeft.petFrame, CGRect(x: 396, y: 156, width: 92, height: 92))
        XCTAssertEqual(topLeft.petAnchorInWindow, CGPoint(x: 442, y: 202))

        let available = CGRect(x: 0, y: 0, width: 1440, height: 900)
        XCTAssertEqual(
            AgentDetachedIslandLayout.preferredPlacement(
                petScreenAnchor: CGPoint(x: 1_300, y: 120),
                bubbleSize: bubble,
                availableFrame: available
            ),
            .topLeft
        )
        XCTAssertEqual(
            AgentDetachedIslandLayout.preferredPlacement(
                petScreenAnchor: CGPoint(x: 90, y: 820),
                bubbleSize: bubble,
                availableFrame: available
            ),
            .bottomRight
        )
    }

    func testCompletionQueueHoverDismissAndPinnedDetachedRouteMatchPingBehavior() throws {
        let settings = AppSettings.shared
        let original = (settings.agentSoundsEnabled, settings.agentNotificationAutoOpen)
        settings.agentSoundsEnabled = false
        settings.agentNotificationAutoOpen = true
        defer {
            settings.agentSoundsEnabled = original.0
            settings.agentNotificationAutoOpen = original.1
        }

        let core = makeAgentCoordinator()
        let working = core.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "notification",
            kind: .processing,
            title: "Notification parity"
        ))
        let model = AgentSurfaceModel(snapshot: working)
        let completed = core.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "notification",
            kind: .completed,
            title: "Notification parity",
            message: "Done"
        ))
        XCTAssertTrue(model.consume(completed))
        let sessionID = try XCTUnwrap(model.projection.sessions.first?.id)
        XCTAssertEqual(model.route(for: .desktop), .completion(sessionID))
        XCTAssertTrue(model.isExpanded)

        model.setNotificationHovered(true)
        model.setNotificationHovered(false)
        XCTAssertNil(model.notificationSessionID)
        XCTAssertFalse(model.isExpanded)

        let channel = AgentResponseChannel(provider: .codex, ownerID: "attention-owner") { _ in true }
        let attention = core.ingest(
            AgentIngressEvent(
                provider: .codex,
                sessionID: "attention",
                kind: .approvalRequested,
                title: "Attention parity",
                requestID: "attention-request",
                responseOwnerID: "attention-owner"
            ),
            responseChannel: channel
        )
        XCTAssertTrue(model.consume(attention))
        let attentionID = try XCTUnwrap(model.projection.sessions.first(where: { $0.needsAttention })?.id)
        XCTAssertEqual(model.detachedRoute(for: .hoverPreview), .attention(attentionID))
        XCTAssertEqual(model.detachedRoute(for: .pinnedList), .sessionList)
        spinRunLoop(seconds: 0.02)
        XCTAssertEqual(model.route(for: .desktop), .attention(attentionID))
    }

    func testCompletionNotificationUsesPingRecencyBlockingAndOneShotRules() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let core = makeAgentCoordinator()
        _ = core.ingest(AgentIngressEvent(
            provider: .claude,
            sessionID: "blocked-completion",
            kind: .processing,
            timestamp: now,
            message: "Working"
        ))
        let initial = core.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "blocker",
            kind: .processing,
            timestamp: now,
            message: "Still active"
        ))
        let model = AgentSurfaceModel(snapshot: initial)

        let blocked = core.ingest(AgentIngressEvent(
            provider: .claude,
            sessionID: "blocked-completion",
            kind: .completed,
            timestamp: now.addingTimeInterval(1),
            message: "Finished first"
        ))
        XCTAssertTrue(model.consume(blocked, now: now.addingTimeInterval(1)))
        XCTAssertNil(model.notificationSessionID)

        let secondCompletion = core.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "blocker",
            kind: .completed,
            timestamp: now.addingTimeInterval(2),
            message: "Finished second"
        ))
        XCTAssertTrue(model.consume(secondCompletion, now: now.addingTimeInterval(2)))
        XCTAssertEqual(model.notificationSessionID, "codex:blocker")
        XCTAssertNotEqual(model.notificationSessionID, "claude:blocked-completion")

        let oldSession = try XCTUnwrap(model.projection.sessions.first(where: {
            $0.id == "claude:blocked-completion"
        }))
        XCTAssertFalse(AgentCompletionNotificationPolicy.isPresentable(
            oldSession,
            sessions: model.projection.sessions,
            now: now.addingTimeInterval(62)
        ))
    }

    func testEveryPinnedProviderMascotMapsAndRenders() throws {
        let mappedKinds = Set(AgentProvider.allCases.map(AgentMascotKind.init(provider:)))
        XCTAssertEqual(mappedKinds, Set(AgentMascotKind.allCases))

        let strip = HStack(spacing: 5) {
            ForEach(AgentMascotKind.allCases) { kind in
                AgentMascotView(kind: kind,
                                     status: .working,
                                     size: 40,
                                     animationTime: 0)
            }
        }
        let rendered = try XCTUnwrap(render(
            strip,
            size: CGSize(width: CGFloat(AgentMascotKind.allCases.count) * 45, height: 48)
        ))
        try captureIfRequested(rendered, name: "agent-island-provider-mascots")
    }

    func testPinnedCESPSoundPackCatalogDiscoversPackAndRejectsPathEscapeAtPlayback() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("n1ko-sound-pack-\(UUID().uuidString)", isDirectory: true)
        let importedPathsKey = "agent.sound.importedPackPaths"
        let defaults = UserDefaults.standard
        let previousImportedPaths = defaults.object(forKey: importedPathsKey)
        defer {
            try? FileManager.default.removeItem(at: root)
            if let previousImportedPaths {
                defaults.set(previousImportedPaths, forKey: importedPathsKey)
            } else {
                defaults.removeObject(forKey: importedPathsKey)
            }
            SoundPackCatalog.shared.refresh()
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let soundURL = root.appendingPathComponent("complete.wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: soundURL)
        let validManifest = """
        {"cesp_version":"1.0","name":"N1KO Test","categories":{"task.complete":{"sounds":[{"file":"complete.wav","label":"Complete"}]}}}
        """
        try validManifest.write(
            to: root.appendingPathComponent("openpeon.json"),
            atomically: true,
            encoding: .utf8
        )

        defaults.set([root.path], forKey: importedPathsKey)
        SoundPackCatalog.shared.refresh()
        let pack = try XCTUnwrap(SoundPackCatalog.shared.pack(for: root.path))
        XCTAssertEqual(pack.displayName, "N1KO Test")

        let outside = root.deletingLastPathComponent().appendingPathComponent("outside.wav")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data([0x52]).write(to: outside)
        let escapedManifest = """
        {"cesp_version":"1.0","name":"Escape","categories":{"task.complete":{"sounds":[{"file":"../outside.wav"}]}}}
        """
        try escapedManifest.write(
            to: root.appendingPathComponent("openpeon.json"),
            atomically: true,
            encoding: .utf8
        )
        SoundPackCatalog.shared.refresh()
        XCTAssertNotNil(SoundPackCatalog.shared.pack(for: root.path))
        XCTAssertFalse(SoundPackCatalog.shared.play(
            event: .taskCompleted,
            packPath: root.path,
            volume: 0
        ))
    }

    func testEmptyProjectionKeepsDesktopIslandAvailableWhenPresentationIsEnabled() {
        let model = AgentSurfaceModel()
        XCTAssertFalse(model.isExpanded)
        XCTAssertNil(model.expansionTrigger)

        model.expand(reason: .hover)
        XCTAssertTrue(model.isExpanded)
        XCTAssertEqual(model.expansionTrigger, .hover)

        model.expand(reason: .click)
        XCTAssertEqual(model.expansionTrigger, .click)

        model.collapse()
        XCTAssertFalse(model.isExpanded)
        XCTAssertNil(model.expansionTrigger)
    }

    func testStateMachineCompletesOneHundredNativeCyclesWithoutDesktopEligibilityInFullscreen() {
        var machine = FullscreenEnvironmentStateMachine()
        let native = evidence(.nativeFullscreen)
        let ordinary = evidence(.ordinary)

        for cycle in 0..<100 {
            machine.beginReconciliation()
            XCTAssertEqual(machine.phase, .entering, "cycle \(cycle)")
            XCTAssertNotEqual(machine.consume(native), .fullscreen(.native), "cycle \(cycle) first sample")
            XCTAssertEqual(machine.consume(native), .fullscreen(.native), "cycle \(cycle)")
            XCTAssertNil(desktopEligible(in: machine.phase), "cycle \(cycle)")

            XCTAssertTrue(machine.beginReveal(), "cycle \(cycle)")
            XCTAssertEqual(machine.phase, .revealing(.native), "cycle \(cycle)")
            machine.dismissReveal()
            XCTAssertEqual(machine.phase, .fullscreen(.native), "cycle \(cycle)")

            machine.beginReconciliation()
            XCTAssertEqual(machine.phase, .exiting, "cycle \(cycle)")
            _ = machine.consume(ordinary)
            XCTAssertEqual(machine.consume(ordinary), .desktop, "cycle \(cycle)")
            XCTAssertEqual(desktopEligible(in: machine.phase), true, "cycle \(cycle)")
        }
    }

    func testRevealRequiresStableFullscreenAndLifecycleReturnsToFailClosedState() {
        XCTAssertGreaterThanOrEqual(AgentSurfaceCoordinator.topEdgeDwell, 0.15)
        XCTAssertLessThanOrEqual(AgentSurfaceCoordinator.topEdgeDwell, 0.20)
        var machine = FullscreenEnvironmentStateMachine()
        XCTAssertFalse(machine.beginReveal())
        _ = machine.consume(evidence(.pseudoFullscreen))
        XCTAssertFalse(machine.beginReveal())
        _ = machine.consume(evidence(.pseudoFullscreen))
        XCTAssertTrue(machine.beginReveal())
        machine.suspend()
        XCTAssertEqual(machine.phase, .suspended)
        XCTAssertFalse(machine.beginReveal())
        machine.resume()
        XCTAssertEqual(machine.phase, .entering)
        _ = machine.consume(evidence(.ordinary))
        XCTAssertEqual(machine.consume(evidence(.ordinary)), .desktop)
    }

    func testWindowEvidenceClassifiesNativePseudoMaximizedAndHelperOwnedModes() {
        let scenarios: [(String, Double, Bool?, Bool, FullscreenClassification)] = [
            ("Safari native fullscreen", 1.0, true, true, .nativeFullscreen),
            ("Chrome native fullscreen without AX", 0.999, nil, true, .nativeFullscreen),
            ("video native fullscreen", 1.0, true, false, .nativeFullscreen),
            ("IDE native fullscreen", 0.995, nil, true, .nativeFullscreen),
            ("presentation mode", 1.0, nil, false, .pseudoFullscreen),
            ("borderless pseudo fullscreen", 0.995, false, false, .pseudoFullscreen),
            ("helper-process-owned fullscreen", 0.999, nil, true, .nativeFullscreen),
            ("maximized but not fullscreen", 0.962, false, false, .ordinary)
        ]

        for scenario in scenarios {
            XCTAssertEqual(
                FullscreenEvidenceClassifier.classify(
                    coverage: scenario.1,
                    accessibilityFullscreen: scenario.2,
                    hasRecentActiveSpaceSignal: scenario.3
                ),
                scenario.4,
                scenario.0
            )
        }
    }

    func testDisplayNormalizationCoversNotchedExternalHorizontalVerticalAndScaledArrangements() {
        let displays = syntheticDisplayMatrix()
        XCTAssertEqual(displays.count, 6)
        XCTAssertTrue(displays[0].hasCameraHousing)
        XCTAssertFalse(displays[1].hasCameraHousing)

        for display in displays {
            let appKitTopLeft = CGPoint(x: display.appKitFrame.minX, y: display.appKitFrame.maxY)
            let quartzTopLeft = DisplayCoordinateNormalizer.quartzPoint(
                fromAppKit: appKitTopLeft,
                on: display
            )
            XCTAssertEqual(quartzTopLeft.x, display.quartzBounds.minX, accuracy: 0.001, display.uuid)
            XCTAssertEqual(quartzTopLeft.y, display.quartzBounds.minY, accuracy: 0.001, display.uuid)

            let appKitBottomRight = CGPoint(x: display.appKitFrame.maxX, y: display.appKitFrame.minY)
            let quartzBottomRight = DisplayCoordinateNormalizer.quartzPoint(
                fromAppKit: appKitBottomRight,
                on: display
            )
            XCTAssertEqual(quartzBottomRight.x, display.quartzBounds.maxX, accuracy: 0.001, display.uuid)
            XCTAssertEqual(quartzBottomRight.y, display.quartzBounds.maxY, accuracy: 0.001, display.uuid)
            XCTAssertEqual(DisplayCoordinateNormalizer.coverage(of: display.quartzBounds, on: display),
                           1, accuracy: 0.0001, display.uuid)
            XCTAssertTrue(display.appKitFrame.contains(
                DisplayCoordinateNormalizer.topEdgeTriggerRect(on: display).center
            ), display.uuid)
        }

        XCTAssertEqual(DisplayCatalog.target(preferredUUID: "right", displays: displays)?.uuid, "right")
        XCTAssertEqual(DisplayCatalog.target(preferredUUID: "missing",
                                             pointer: CGPoint(x: -900, y: 500),
                                             displays: displays)?.uuid,
                       "left")
    }

    func testImmutableProjectionComposesExactlyOncePerAgentGeneration() {
        AgentSurfaceDiagnostics.reset()
        let core = makeAgentCoordinator()
        let first = core.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "projection",
            kind: .started,
            title: "Build WP4",
            usage: AgentUsage(inputTokens: 100, outputTokens: 10)
        ))
        let model = AgentSurfaceModel(snapshot: .empty)

        XCTAssertTrue(model.consume(first))
        XCTAssertFalse(model.consume(first))
        XCTAssertEqual(model.projection.generation, first.generation)
        XCTAssertEqual(model.projection.primarySession?.title, "Build WP4")
        XCTAssertEqual(model.projection.usage.totalTokens, 110)
        XCTAssertEqual(AgentSurfaceDiagnostics.snapshot().counters["snapshotComposition"], 1)

        let second = core.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "projection",
            kind: .processing,
            title: "Build WP4",
            usage: AgentUsage(inputTokens: 140, outputTokens: 30)
        ))
        XCTAssertTrue(model.consume(second))
        XCTAssertEqual(model.projection.generation, second.generation)
        XCTAssertEqual(model.projection.primarySession?.usage.totalTokens, 170)
        XCTAssertEqual(AgentSurfaceDiagnostics.snapshot().counters["snapshotComposition"], 2)
    }

    func testPinnedRouteResolutionAndBoundedConversationProjection() throws {
        let core = makeAgentCoordinator()
        _ = core.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "route",
            kind: .promptSubmitted,
            title: "Route parity",
            message: "Show the Ping-style routes"
        ))
        let processing = core.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "route",
            kind: .processing,
            title: "Route parity",
            message: "Building the hover conversation preview"
        ))
        let model = AgentSurfaceModel(snapshot: processing)

        model.expand(reason: .hover)
        XCTAssertEqual(model.route(for: .desktop), .hoverDashboard)
        model.expand(reason: .click)
        XCTAssertEqual(model.route(for: .desktop), .sessionList)

        let session = try XCTUnwrap(model.projection.sessions.first)
        XCTAssertEqual(session.conversationItems.map(\.kind), [.user, .assistant])
        model.openConversation(session)
        XCTAssertEqual(model.route(for: .desktop), .conversation(session.id))
        model.showSessionList()
        XCTAssertEqual(model.route(for: .desktop), .sessionList)

        let channel = AgentResponseChannel(provider: .codex, ownerID: "route-owner") { _ in true }
        let attention = core.ingest(
            AgentIngressEvent(
                provider: .codex,
                sessionID: "route",
                kind: .approvalRequested,
                title: "Approve route",
                message: "Continue?",
                requestID: "route-request",
                responseOwnerID: "route-owner"
            ),
            responseChannel: channel
        )
        XCTAssertTrue(model.consume(attention))
        XCTAssertEqual(model.route(for: .desktop), .attention(session.id))
    }

    func testPingRouteAndDetachedSurfacesRender() throws {
        let originalTMUX = AppSettings.shared.agentTMUXEnabled
        AppSettings.shared.agentTMUXEnabled = true
        defer { AppSettings.shared.agentTMUXEnabled = originalTMUX }
        let core = makeAgentCoordinator()
        let tmuxTarget = try AgentTMUXTarget(session: "n1ko", window: "1", pane: "0")
        _ = core.ingest(AgentIngressEvent(
            provider: .claude,
            sessionID: "claude-list",
            kind: .promptSubmitted,
            cwd: "/tmp/N1KO-STATE",
            title: "Refine the Island",
            message: "Match Ping Island",
            navigation: AgentNavigationContext(
                terminalBundleIdentifier: "com.apple.Terminal",
                tmuxTarget: tmuxTarget
            )
        ))
        _ = core.ingest(AgentIngressEvent(
            provider: .claude,
            sessionID: "claude-list",
            kind: .processing,
            cwd: "/tmp/N1KO-STATE",
            title: "Refine the Island",
            message: "Rebuilding the hover dashboard"
        ))
        _ = core.ingest(AgentIngressEvent(
            provider: .claude,
            sessionID: "claude-list",
            kind: .processing,
            cwd: "/tmp/N1KO-STATE",
            title: "Refine the Island",
            toolName: "Bash",
            toolInput: #"{"command":"swift test --filter WP4AgentSurfaceTests"}"#,
            requestID: "render-tool"
        ))
        _ = core.ingest(AgentIngressEvent(
            provider: .claude,
            sessionID: "claude-list",
            kind: .toolResult,
            cwd: "/tmp/N1KO-STATE",
            toolResult: "21 tests passed",
            toolSucceeded: true,
            requestID: "render-tool"
        ))
        let snapshot = core.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "codex-list",
            kind: .processing,
            cwd: "/tmp/N1KO-STATE",
            title: "Verify route parity",
            message: "Running focused tests",
            usage: AgentUsage(inputTokens: 8_400, cachedInputTokens: 2_100, outputTokens: 940),
            usageWindows: [
                AgentUsageWindow(key: "primary", label: "5h", usedPercentage: 22),
                AgentUsageWindow(key: "secondary", label: "7d", usedPercentage: 64)
            ]
        ))
        let model = AgentSurfaceModel(snapshot: snapshot)
        let root = AgentIslandRootView(model: model,
                                       surface: .desktop,
                                       onResponse: { _ in },
                                       onOpenAgentCenter: {},
                                       onDismiss: {},
                                       onHoverChanged: { _ in })

        model.expand(reason: .click)
        let listSize = AgentIslandLayout.size(surface: .desktop,
                                              isExpanded: true,
                                              trigger: .click,
                                              projection: model.projection)
        let list = try XCTUnwrap(render(root, size: listSize))
        try captureIfRequested(list, name: "agent-island-session-list")

        model.expand(reason: .hover)
        let hoverSize = AgentIslandLayout.size(surface: .desktop,
                                               isExpanded: true,
                                               trigger: .hover,
                                               projection: model.projection)
        let hover = try XCTUnwrap(render(root, size: hoverSize))
        try captureIfRequested(hover, name: "agent-island-hover-dashboard")

        let session = try XCTUnwrap(model.projection.sessions.first(where: { $0.provider == .claude }))
        model.openConversation(session)
        let conversationSize = AgentIslandLayout.size(
            surface: .desktop,
            isExpanded: true,
            trigger: .click,
            projection: model.projection,
            route: model.route(for: .desktop)
        )
        let conversation = try XCTUnwrap(render(root, size: conversationSize))
        try captureIfRequested(conversation, name: "agent-island-conversation")

        model.showSessionList()
        let detached = AgentDetachedIslandView(model: model,
                                               onResponse: { _ in },
                                               onOpenAgentCenter: {},
                                               onReattach: {},
                                               onModeChanged: { _ in },
                                               onSessionAction: { _ in },
                                               initiallyExpanded: true)
        let detachedRoute = model.detachedRoute(for: .pinnedList)
        let detachedLayout = AgentDetachedIslandLayout.windowLayout(
            bubbleSize: AgentDetachedIslandLayout.bubbleSize(
                route: detachedRoute,
                projection: model.projection
            ),
            placement: .topLeft
        )
        let detachedRender = try XCTUnwrap(render(detached, size: detachedLayout.containerSize))
        try captureIfRequested(detachedRender, name: "agent-island-detached-expanded")
    }

    func testCompactExpandedInterventionCompletionSessionAndUsageSurfacesRenderWithReduceMotion() throws {
        let core = makeAgentCoordinator()
        _ = core.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "working",
            kind: .processing,
            title: "Implement Agent Island",
            usage: AgentUsage(inputTokens: 2_400, cachedInputTokens: 800, outputTokens: 450)
        ))
        _ = core.ingest(AgentIngressEvent(
            provider: .codex,
            sessionID: "complete",
            kind: .completed,
            title: "Run tests",
            usage: AgentUsage(inputTokens: 900, outputTokens: 120)
        ))
        let channel = AgentResponseChannel(provider: .claude, ownerID: "render-owner") { _ in true }
        let snapshot = core.ingest(
            AgentIngressEvent(
                provider: .claude,
                sessionID: "approval",
                kind: .approvalRequested,
                title: "Approve build",
                message: "Run the native smoke build?",
                toolName: "shell",
                requestID: "render-request",
                responseOwnerID: "render-owner"
            ),
            responseChannel: channel
        )
        let model = AgentSurfaceModel(snapshot: snapshot)
        var responseCount = 0

        let compact = AgentIslandRootView(
            model: model,
            surface: .desktop,
            onResponse: { _ in responseCount += 1 },
            onOpenAgentCenter: {},
            onDismiss: {},
            onHoverChanged: { _ in }
        )
        let compactRender = try XCTUnwrap(render(compact, size: AgentIslandLayout.compactSize))
        try captureIfRequested(compactRender, name: "agent-island-compact")

        model.isExpanded = true
        let clickedSize = AgentIslandLayout.size(surface: .desktop,
                                                 isExpanded: true,
                                                 trigger: .click,
                                                 projection: model.projection)
        let expandedRender = try XCTUnwrap(render(compact, size: clickedSize))
        try captureIfRequested(expandedRender, name: "agent-island-click-expanded")
        let reveal = AgentIslandRootView(
            model: model,
            surface: .fullscreenReveal,
            onResponse: { _ in responseCount += 1 },
            onOpenAgentCenter: {},
            onDismiss: {},
            onHoverChanged: { _ in }
        )
        let revealSize = AgentIslandLayout.size(surface: .fullscreenReveal,
                                                isExpanded: false,
                                                trigger: nil,
                                                projection: model.projection)
        let revealRender = try XCTUnwrap(render(reveal, size: revealSize))
        try captureIfRequested(revealRender, name: "agent-island-fullscreen-reveal")
        XCTAssertLessThanOrEqual(Theme.Motion.reduced, 0.10)
        XCTAssertEqual(responseCount, 0)
        XCTAssertEqual(model.projection.sessions.count, 3)
        XCTAssertEqual(model.projection.attentionCount, 1)
        XCTAssertEqual(model.projection.completionCount, 1)
        XCTAssertGreaterThan(model.projection.usage.totalTokens, 0)

        let emptyQuestionSnapshot = core.ingest(
            AgentIngressEvent(
                provider: .claude,
                sessionID: "empty-question",
                kind: .answerRequested,
                title: "Answer request",
                message: "Provide a short answer",
                requestID: "empty-question-request",
                responseOwnerID: "render-owner"
            ),
            responseChannel: channel
        )
        XCTAssertTrue(model.consume(emptyQuestionSnapshot))
        XCTAssertTrue(model.projection.primarySession?.intervention?.questions.isEmpty == true)
        XCTAssertNotNil(render(compact, size: AgentIslandLayout.size(
            surface: .desktop,
            isExpanded: true,
            trigger: .click,
            projection: model.projection
        )))

        let questionSnapshot = core.ingest(
            AgentIngressEvent(
                provider: .claude,
                sessionID: "question-grid",
                kind: .answerRequested,
                cwd: "/tmp/N1KO-STATE",
                title: "Choose the next focus",
                message: "Select one direction before the session continues.",
                requestID: "question-grid-request",
                questions: [
                    AgentQuestion(
                        id: "focus",
                        header: "Today's focus",
                        prompt: "What would you like to work on today?",
                        options: [
                            AgentQuestionOption(label: "Explore a codebase", description: "Navigate and understand an existing project"),
                            AgentQuestionOption(label: "Write new code", description: "Build something from scratch or add features"),
                            AgentQuestionOption(label: "Debug an issue", description: "Fix a bug or resolve an error"),
                            AgentQuestionOption(label: "Review or refactor", description: "Improve existing code quality")
                        ],
                        allowsOther: false
                    )
                ],
                responseOwnerID: "render-owner"
            ),
            responseChannel: channel
        )
        XCTAssertTrue(model.consume(questionSnapshot))
        model.updateOpenedMeasuredContentHeight(360)
        let questionSize = AgentIslandLayout.size(
            surface: .desktop,
            isExpanded: true,
            trigger: .notification,
            projection: model.projection,
            route: model.route(for: .desktop),
            measuredContentHeight: model.openedMeasuredContentHeight
        )
        let questionRender = try XCTUnwrap(render(compact, size: questionSize))
        try captureIfRequested(questionRender, name: "agent-island-question")
    }

    func testSurfaceResponseUsesCoreOwnerCapabilityRouteWithoutSecondSessionStore() throws {
        let core = makeAgentCoordinator()
        var actions: [AgentResponseAction] = []
        let channel = AgentResponseChannel(provider: .claude, ownerID: "n1ko-owner") {
            actions.append($0)
            return true
        }
        let snapshot = core.ingest(
            AgentIngressEvent(
                provider: .claude,
                sessionID: "approval",
                kind: .approvalRequested,
                title: "Approve command",
                requestID: "request-1",
                responseOwnerID: "n1ko-owner"
            ),
            responseChannel: channel
        )
        let intervention = try XCTUnwrap(snapshot.sessions.first?.intervention)
        let surface = AgentSurfaceCoordinator(agentCoordinator: core, onOpenAgentCenter: {})
        defer { surface.shutdown() }

        surface.routeResponseForTesting(AgentSurfaceResponseRequest(
            provider: .claude,
            sessionID: "approval",
            requestID: intervention.requestID,
            ownerID: intervention.responseOwnerID,
            capability: intervention.responseCapability,
            action: .approve(scope: "session")
        ))

        XCTAssertEqual(actions, [.approve(scope: "session")])
        XCTAssertEqual(core.snapshot.sessions.first?.phase, .processing)
        XCTAssertNil(core.snapshot.sessions.first?.intervention)
        XCTAssertEqual(surface.model.responseStatus, "Response sent".loc)
    }

    func testCoordinatorRevealDismissalAndShutdownRestoreMonitorTaskPanelBaseline() {
        let settings = AppSettings.shared
        let original = (settings.agentBehaviorEnabled,
                        settings.agentPresentationEnabled,
                        settings.agentFullscreenRevealEnabled)
        settings.agentBehaviorEnabled = true
        settings.agentPresentationEnabled = true
        settings.agentFullscreenRevealEnabled = true
        defer {
            settings.agentBehaviorEnabled = original.0
            settings.agentPresentationEnabled = original.1
            settings.agentFullscreenRevealEnabled = original.2
        }

        let core = makeAgentCoordinator()
        _ = core.ingest(AgentIngressEvent(provider: .codex,
                                          sessionID: "active",
                                          kind: .processing,
                                          title: "Active task"))
        AgentSurfaceDiagnostics.reset()
        let surface = AgentSurfaceCoordinator(
            agentCoordinator: core,
            preferences: settings,
            evidenceSampler: FullscreenEvidenceSampler(processIDOverride: getpid()),
            onOpenAgentCenter: {}
        )
        let display = syntheticDisplayMatrix()[1]
        surface.forceFullscreenForTesting(.native, display: display)

        XCTAssertEqual(surface.phaseForTesting, .fullscreen(.native))
        XCTAssertNil(surface.revealPanel)
        XCTAssertEqual(AgentSurfaceDiagnostics.snapshot().activeGlobalMonitors, 1)
        XCTAssertTrue(surface.completeTopEdgeDwellForTesting())
        XCTAssertTrue(surface.revealPanel?.isVisible == true)

        surface.handlePointerForTesting(at: CGPoint(x: display.appKitFrame.minX + 20,
                                                    y: display.appKitFrame.midY))
        XCTAssertFalse(surface.revealPanel?.isVisible == true)
        XCTAssertEqual(surface.phaseForTesting, .fullscreen(.native))

        surface.forceFullscreenForTesting(.native, display: display)
        XCTAssertTrue(surface.completeTopEdgeDwellForTesting())
        surface.dismissReveal(reason: "escape-test")
        XCTAssertFalse(surface.revealPanel?.isVisible == true)

        surface.suspend(reason: "test-sleep")
        XCTAssertEqual(surface.phaseForTesting, .suspended)
        XCTAssertFalse(surface.desktopPanel?.isVisible == true)
        XCTAssertFalse(surface.revealPanel?.isVisible == true)
        XCTAssertEqual(AgentSurfaceDiagnostics.snapshot().activeGlobalMonitors, 0)
        surface.shutdown()
        XCTAssertEqual(AgentSurfaceDiagnostics.snapshot().activeRetryTasks, 0)
        XCTAssertEqual(AgentSurfaceDiagnostics.snapshot().activeGlobalMonitors, 0)
    }

    func testRapidSpaceReconciliationCancelsStaleRetriesAndReturnsToBaseline() {
        let settings = AppSettings.shared
        let originalPresentation = settings.agentPresentationEnabled
        settings.agentPresentationEnabled = false
        defer { settings.agentPresentationEnabled = originalPresentation }

        AgentSurfaceDiagnostics.reset()
        let surface = AgentSurfaceCoordinator(agentCoordinator: nil, preferences: settings,
                                              onOpenAgentCenter: {})
        surface.install()
        for index in 0..<100 {
            surface.reconcile(reason: "rapid-\(index)", activeSpaceChanged: index.isMultiple(of: 2))
        }
        surface.shutdown()
        spinRunLoop(seconds: 0.05)

        let diagnostics = AgentSurfaceDiagnostics.snapshot()
        XCTAssertEqual(diagnostics.activeRetryTasks, 0)
        XCTAssertEqual(diagnostics.activeGlobalMonitors, 0)
        XCTAssertFalse(surface.desktopPanel?.isVisible == true)
        XCTAssertFalse(surface.revealPanel?.isVisible == true)
    }

    func testAgentCenterRendersInAllLocalizationsAtMinimumWindowSize() throws {
        let originalBundle = LocalizationManager.shared.bundle
        defer { LocalizationManager.shared.useBundleForTesting(originalBundle) }
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let hub = MonitorHub()

        for language in ["en", "zh-Hans", "zh-Hant"] {
            let path = repositoryRoot.appendingPathComponent("Localization")
                .appendingPathComponent("\(language).lproj").path
            let bundle = try XCTUnwrap(Bundle(path: path))
            LocalizationManager.shared.useBundleForTesting(bundle)
            let view = SettingsView(
                fans: hub.fans,
                hub: hub,
                initialTab: .agentCenter,
                navigation: SettingsNavigationModel(selectedTab: .agentCenter),
                agentModel: AgentSurfaceModel()
            )
            let hosting = NSHostingView(rootView: view)
            hosting.frame = NSRect(origin: .zero, size: SettingsLayoutPolicy.minimumSize)
            hosting.layoutSubtreeIfNeeded()
            XCTAssertEqual(hosting.frame.size, SettingsLayoutPolicy.minimumSize, language)
        }
    }

    func testPinnedSoundAndMascotSettingsRenderWithCompleteEventModel() throws {
        let settings = AppSettings.shared
        let originalAppearance = NSApp.appearance
        let originalSurfaceMode = settings.surfaceMode
        let originalMode = settings.soundThemeMode
        let originalVolume = settings.soundVolume
        let originalEnabled = NotificationEvent.allCases.map(AppSettings.isSoundEnabled(for:))
        let originalSystemSounds = NotificationEvent.allCases.map(AppSettings.sound(for:))
        let originalBundledSounds = NotificationEvent.allCases.map(AppSettings.bundledSound(for:))
        NSApp.appearance = NSAppearance(named: .darkAqua)
        defer {
            NSApp.appearance = originalAppearance
            settings.surfaceMode = originalSurfaceMode
            settings.soundThemeMode = originalMode
            settings.soundVolume = originalVolume
            for (index, event) in NotificationEvent.allCases.enumerated() {
                AppSettings.setSoundEnabled(originalEnabled[index], for: event)
                AppSettings.setSound(originalSystemSounds[index], for: event)
                AppSettings.setBundledSound(originalBundledSounds[index], for: event)
            }
        }

        XCTAssertEqual(NotificationEvent.allCases.count, 5)
        XCTAssertEqual(SoundThemeMode.allCases.count, 3)
        XCTAssertEqual(IslandSurfaceMode.allCases.count, 2)
        settings.soundVolume = 0.65

        for surfaceMode in IslandSurfaceMode.allCases {
            settings.surfaceMode = surfaceMode
            let rendered = try XCTUnwrap(render(
                IslandSettingsContent(),
                size: CGSize(width: 740, height: 1_080)
            ))
            try captureIfRequested(rendered, name: "ping-source-island-settings-\(surfaceMode.rawValue)")
        }

        for mode in SoundThemeMode.allCases {
            settings.soundThemeMode = mode
            let rendered = try XCTUnwrap(render(
                SoundSettingsContent(),
                size: CGSize(width: 740, height: 1_080)
            ))
            try captureIfRequested(rendered, name: "ping-source-sound-settings-\(mode.rawValue)")
        }

        let mascot = try XCTUnwrap(render(
            ZStack {
                Color.black
                MascotSettingsView()
            }
            .preferredColorScheme(.dark),
            size: CGSize(width: 740, height: 780)
        ))
        try captureIfRequested(mascot, name: "ping-source-mascot-settings")
    }

    func testPinnedSurfaceModeSettingSwitchesTheN1KOWindowOwner() {
        let settings = AppSettings.shared
        let originalMode = settings.surfaceMode
        let originalPresentation = settings.agentPresentationEnabled
        settings.agentPresentationEnabled = false
        settings.surfaceMode = .floatingPet
        let surface = AgentSurfaceCoordinator(
            agentCoordinator: makeAgentCoordinator(),
            preferences: settings,
            onOpenAgentCenter: {}
        )
        defer {
            surface.shutdown()
            settings.surfaceMode = originalMode
            settings.agentPresentationEnabled = originalPresentation
        }

        surface.install()
        XCTAssertTrue(surface.isDetachedForTesting)

        settings.surfaceMode = .notch
        spinRunLoop(seconds: 0.05)
        XCTAssertFalse(surface.isDetachedForTesting)

        settings.surfaceMode = .floatingPet
        spinRunLoop(seconds: 0.05)
        XCTAssertTrue(surface.isDetachedForTesting)
    }

    func testPinnedIslandAudioAssetsAreCompleteWAVSet() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let soundsDirectory = repositoryRoot.appendingPathComponent("Resources/Sounds", isDirectory: true)
        let expected = Set([
            "8bit_approval_alert.wav", "8bit_boot_jingle.wav", "8bit_complete_ding.wav",
            "8bit_error_buzz.wav", "8bit_hurt.wav", "8bit_item_pickup.wav",
            "8bit_menu_highlight.wav", "8bit_menu_select.wav", "8bit_power_up.wav",
            "8bit_start_chime.wav", "8bit_submit_blip.wav", "8bit_win_jingle.wav",
            "bubbles_pop.wav"
        ])
        let actual = try Set(
            FileManager.default.contentsOfDirectory(atPath: soundsDirectory.path)
                .filter { $0.hasSuffix(".wav") }
        )
        XCTAssertEqual(actual, expected)

        for name in expected {
            let data = try Data(contentsOf: soundsDirectory.appendingPathComponent(name))
            XCTAssertGreaterThan(data.count, 44, name)
            XCTAssertTrue(data.starts(with: [0x52, 0x49, 0x46, 0x46]), name)
            XCTAssertNotNil(
                NSSound(contentsOf: soundsDirectory.appendingPathComponent(name), byReference: false),
                name
            )
        }
    }

    func testPseudoFullscreenHideAndStableDetectionLatencyWhenOptedIn() throws {
        guard ProcessInfo.processInfo.environment["N1KO_RUN_PSEUDO_FULLSCREEN_LATENCY"] == "1" else {
            throw XCTSkip("Set N1KO_RUN_PSEUDO_FULLSCREEN_LATENCY=1 for the live WindowServer latency gate.")
        }
        guard let screen = NSScreen.main,
              let display = DisplayCatalog.descriptor(for: screen) else {
            throw XCTSkip("No NSScreen available")
        }

        let settings = AppSettings.shared
        let original = (settings.agentBehaviorEnabled,
                        settings.agentPresentationEnabled,
                        settings.agentFullscreenRevealEnabled,
                        settings.agentTargetDisplayUUID)
        settings.agentBehaviorEnabled = true
        settings.agentPresentationEnabled = true
        settings.agentFullscreenRevealEnabled = true
        settings.agentTargetDisplayUUID = display.uuid
        defer {
            settings.agentBehaviorEnabled = original.0
            settings.agentPresentationEnabled = original.1
            settings.agentFullscreenRevealEnabled = original.2
            settings.agentTargetDisplayUUID = original.3
        }

        let core = makeAgentCoordinator()
        _ = core.ingest(AgentIngressEvent(provider: .codex,
                                          sessionID: "pseudo-latency",
                                          kind: .processing,
                                          title: "Pseudo fullscreen latency"))
        let surface = AgentSurfaceCoordinator(
            agentCoordinator: core,
            preferences: settings,
            evidenceSampler: FullscreenEvidenceSampler(processIDOverride: getpid()),
            onOpenAgentCenter: {}
        )
        let primary = NSWindow(
            contentRect: NSRect(x: screen.frame.midX - 260, y: screen.frame.midY - 180,
                                width: 520, height: 360),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        defer {
            surface.shutdown()
            primary.orderOut(nil)
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.activate(ignoringOtherApps: true)
        primary.makeKeyAndOrderFront(nil)
        surface.install()
        spinRunLoop(seconds: 0.45)
        XCTAssertEqual(surface.phaseForTesting, .desktop)
        XCTAssertTrue(surface.desktopPanel?.isVisible == true)

        let started = DispatchTime.now().uptimeNanoseconds
        primary.setFrame(screen.frame, display: true, animate: false)
        surface.reconcile(reason: "pseudo-harness")
        var hiddenAt: UInt64?
        var stableAt: UInt64?
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline, stableAt == nil {
            if hiddenAt == nil,
               let number = surface.desktopPanel?.windowNumber,
               !windowIsOnScreen(number) {
                hiddenAt = DispatchTime.now().uptimeNanoseconds
            }
            if surface.phaseForTesting == .fullscreen(.pseudo) {
                stableAt = DispatchTime.now().uptimeNanoseconds
            }
            spinRunLoop(seconds: 0.005)
        }

        let hiddenMS = Double(try XCTUnwrap(hiddenAt) - started) / 1_000_000
        let stableMS = Double(try XCTUnwrap(stableAt) - started) / 1_000_000
        print(String(format: "WP4_PSEUDO_FULLSCREEN_HIDE_MS=%.3f STABLE_MS=%.3f", hiddenMS, stableMS))
        XCTAssertLessThanOrEqual(hiddenMS, 200)
        XCTAssertLessThanOrEqual(stableMS, 200)
    }

    private func evidence(_ classification: FullscreenClassification) -> FullscreenEvidence {
        FullscreenEvidence(classification: classification,
                           coverage: classification == .ordinary ? 0.8 : 1,
                           ownerPID: nil,
                           sampledAtUptimeNanoseconds: DispatchTime.now().uptimeNanoseconds)
    }

    private func desktopEligible(in phase: FullscreenEnvironmentPhase) -> Bool? {
        switch phase {
        case .desktop: return true
        case .fullscreen, .revealing: return nil
        case .entering, .exiting, .suspended: return false
        }
    }

    private func makeAgentCoordinator() -> AgentSessionCoordinator {
        AgentSessionCoordinator(
            configuration: AgentCoreConfiguration(enabled: false),
            store: AgentSessionStore(),
            ingressCoordinator: AgentIngressCoordinator(sources: []),
            publicationQueue: .main
        )
    }

    private func syntheticDisplayMatrix() -> [DisplayDescriptor] {
        [
            DisplayDescriptor(displayID: 1, uuid: "built-in-notched", localizedName: "Built-in",
                              quartzBounds: CGRect(x: 0, y: 0, width: 3024, height: 1964),
                              appKitFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                              backingScaleFactor: 2, safeAreaTop: 32),
            DisplayDescriptor(displayID: 2, uuid: "right", localizedName: "External Right",
                              quartzBounds: CGRect(x: 3024, y: 0, width: 1920, height: 1080),
                              appKitFrame: CGRect(x: 1512, y: 0, width: 1920, height: 1080),
                              backingScaleFactor: 1, safeAreaTop: 0),
            DisplayDescriptor(displayID: 3, uuid: "left", localizedName: "External Left",
                              quartzBounds: CGRect(x: -2560, y: 0, width: 2560, height: 1440),
                              appKitFrame: CGRect(x: -1280, y: 0, width: 1280, height: 720),
                              backingScaleFactor: 2, safeAreaTop: 0),
            DisplayDescriptor(displayID: 4, uuid: "above", localizedName: "External Above",
                              quartzBounds: CGRect(x: 0, y: -2160, width: 3840, height: 2160),
                              appKitFrame: CGRect(x: 0, y: 982, width: 1920, height: 1080),
                              backingScaleFactor: 2, safeAreaTop: 0),
            DisplayDescriptor(displayID: 5, uuid: "below", localizedName: "External Below",
                              quartzBounds: CGRect(x: 0, y: 1964, width: 1920, height: 1080),
                              appKitFrame: CGRect(x: 0, y: -1080, width: 1920, height: 1080),
                              backingScaleFactor: 1, safeAreaTop: 0),
            DisplayDescriptor(displayID: 6, uuid: "menu-reassigned", localizedName: "Menu Display",
                              quartzBounds: CGRect(x: 4944, y: 200, width: 3008, height: 1692),
                              appKitFrame: CGRect(x: 3432, y: 100, width: 1504, height: 846),
                              backingScaleFactor: 2, safeAreaTop: 0)
        ]
    }

    private func windowIsOnScreen(_ windowNumber: Int) -> Bool {
        guard let list = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                as? [[String: Any]] else { return false }
        return list.contains {
            ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == windowNumber
        }
    }

    private func render<Content: View>(_ view: Content, size: NSSize) -> NSBitmapImageRep? {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return nil
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        return representation
    }

    private func captureIfRequested(_ representation: NSBitmapImageRep, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["N1KO_CAPTURE_WP4_SURFACES"],
              !directory.isEmpty else { return }
        let target = URL(fileURLWithPath: directory, isDirectory: true)
            .appendingPathComponent("\(name).png")
        let data = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        try data.write(to: target, options: .atomic)
    }

    private func spinRunLoop(seconds: TimeInterval) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.main.run(mode: .default, before: min(end, Date().addingTimeInterval(0.01)))
        }
    }
}

private extension CGRect {
    var center: CGPoint { CGPoint(x: midX, y: midY) }
}
