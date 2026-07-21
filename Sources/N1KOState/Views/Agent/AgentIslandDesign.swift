import N1KOAgentCore
import SwiftUI

// N1KO modification notice:
// The Island route vocabulary, quadratic outline, and provider-mascot behavior
// in this file are adapted from Apache-2.0 Ping Island commit da130d6. They are
// integrated with N1KO snapshot, settings, and fullscreen ownership.
enum AgentIslandExpansionTrigger: Equatable {
    case click
    case hover
    case notification
    case pinnedList
}

enum AgentIslandRoute: Equatable {
    case sessionList
    case hoverDashboard
    case attention(String)
    case completion(String)
    case conversation(String)
}

enum AgentSessionSurfaceAction {
    case focus(AgentSessionSnapshot)
    case archive(AgentSessionSnapshot)
}

enum AgentIslandLayout {
    static let compactSize = CGSize(width: 266, height: 32)
    static let clickWidth: CGFloat = 520
    static let hoverWidth: CGFloat = 600
    static let revealWidth: CGFloat = 600
    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 14
    static let openTopRadius: CGFloat = 19
    static let openBottomRadius: CGFloat = 24
    static let hoverActivationDelay: TimeInterval = 0.24
    static let transitionDuration: TimeInterval = 0.25
    static let reducedTransitionDuration: TimeInterval = 0.08
    static let defaultMaximumPanelHeight: CGFloat = 580

    static func size(
        surface: AgentSurfaceKind,
        isExpanded: Bool,
        trigger: AgentIslandExpansionTrigger?,
        projection: AgentSurfaceProjection,
        route: AgentIslandRoute? = nil,
        measuredContentHeight: CGFloat? = nil,
        availableDisplaySize: CGSize? = nil
    ) -> CGSize {
        guard surface == .fullscreenReveal || isExpanded else { return compactSize }

        let resolvedTrigger: AgentIslandExpansionTrigger = surface == .fullscreenReveal
            ? .hover
            : (trigger ?? .click)
        let maximumHeight = availableDisplaySize.map {
            min(defaultMaximumPanelHeight, max(compactSize.height + 24, $0.height - 120))
        } ?? defaultMaximumPanelHeight
        let width: CGFloat
        if let route, case .conversation = route {
            width = availableDisplaySize.map { min($0.width - 64, hoverWidth) } ?? hoverWidth
            return CGSize(width: width, height: maximumHeight)
        }
        switch (surface, resolvedTrigger) {
        case (.fullscreenReveal, _):
            width = availableDisplaySize.map { min($0.width - 64, revealWidth) } ?? revealWidth
        case (.desktop, .hover), (.desktop, .notification):
            width = availableDisplaySize.map { min($0.width - 64, hoverWidth) } ?? hoverWidth
        case (.desktop, .click), (.desktop, .pinnedList):
            width = availableDisplaySize.map { min($0.width * 0.44, clickWidth) } ?? clickWidth
        }

        return CGSize(width: width, height: expandedHeight(
            surface: surface,
            trigger: resolvedTrigger,
            projection: projection,
            measuredContentHeight: measuredContentHeight,
            maximumHeight: maximumHeight
        ))
    }

    static func panelFrame(
        on displayFrame: CGRect,
        surface: AgentSurfaceKind,
        isExpanded: Bool,
        trigger: AgentIslandExpansionTrigger?,
        projection: AgentSurfaceProjection,
        route: AgentIslandRoute? = nil,
        measuredContentHeight: CGFloat? = nil
    ) -> CGRect {
        let size = size(surface: surface,
                        isExpanded: isExpanded,
                        trigger: trigger,
                        projection: projection,
                        route: route,
                        measuredContentHeight: measuredContentHeight,
                        availableDisplaySize: displayFrame.size)
        return CGRect(x: displayFrame.midX - size.width / 2,
                      y: displayFrame.maxY - size.height,
                      width: size.width,
                      height: size.height)
    }

    private static func expandedHeight(
        surface: AgentSurfaceKind,
        trigger: AgentIslandExpansionTrigger,
        projection: AgentSurfaceProjection,
        measuredContentHeight: CGFloat?,
        maximumHeight: CGFloat
    ) -> CGFloat {
        if let measuredContentHeight, measuredContentHeight > 0 {
            return min(maximumHeight,
                       max(compactSize.height + 24,
                           compactSize.height + 12 + ceil(measuredContentHeight)))
        }
        if let intervention = projection.primarySession?.intervention {
            if intervention.kind == .approval { return 270 }
            let questionRows = intervention.questions.reduce(0) { partial, question in
                partial + max(question.options.count, 1)
            }
            return min(440, max(240, 170 + CGFloat(questionRows) * 52))
        }

        if trigger == .notification,
           projection.primarySession?.phase == .completed {
            return 190
        }

        if trigger == .hover || trigger == .notification || surface == .fullscreenReveal {
            let rows = min(max(projection.sessions.count, 1), 3)
            return min(330, max(150, 44 + CGFloat(rows) * 67))
        }

        let rows = min(max(projection.sessions.count, 1), 6)
        return min(410, max(150, 46 + CGFloat(rows) * 58))
    }
}

enum AgentDetachedIslandLayout {
    static let petVisualFrame: CGFloat = 74
    static let petHitFrame: CGFloat = 92
    static let mascotDisplaySize: CGFloat = 46
    static let mascotRenderScale: CGFloat = 1.75
    static let bubbleGap: CGFloat = 8
    static let leftBubbleGap: CGFloat = 2
    static let windowGutter: CGFloat = 2
    static let bubbleWidth: CGFloat = 392
    static let bubbleHeight: CGFloat = 220
    static let compactSize = CGSize(width: petHitFrame, height: petHitFrame)
    static let expandedSize = windowLayout(
        bubbleSize: CGSize(width: bubbleWidth, height: bubbleHeight),
        placement: .topLeft
    ).containerSize

    static func bubbleSize(
        route: AgentIslandRoute,
        projection: AgentSurfaceProjection
    ) -> CGSize {
        switch route {
        case .sessionList:
            let rows = projection.sessions.prefix(12).reduce(CGFloat(0)) { partial, session in
                if session.needsAttention { return partial + 86 }
                if !session.phase.isTerminal { return partial + 74 }
                return partial + 56
            }
            let spacing = CGFloat(max(0, min(projection.sessions.count, 12) - 1)) * 2
            return CGSize(width: 448, height: min(520, max(96, rows + spacing + 8)))
        case .hoverDashboard:
            let count = max(min(projection.sessions.count, 3), 1)
            return CGSize(width: bubbleWidth,
                          height: min(520, max(120, 18 + CGFloat(count) * 94)))
        case .attention(let id):
            let isQuestion = projection.sessions.first(where: { $0.id == id })?
                .intervention?.kind == .question
            return CGSize(width: bubbleWidth, height: isQuestion ? 316 : 228)
        case .completion:
            return CGSize(width: bubbleWidth, height: 180)
        case .conversation:
            return CGSize(width: 500, height: AgentIslandLayout.defaultMaximumPanelHeight)
        }
    }

    static func windowLayout(
        bubbleSize: CGSize?,
        placement: AgentDetachedBubblePlacement
    ) -> AgentDetachedWindowLayout {
        let petSize = CGSize(width: petHitFrame, height: petHitFrame)
        guard let bubbleSize else {
            let frame = CGRect(origin: .zero, size: petSize)
            return AgentDetachedWindowLayout(
                containerSize: petSize,
                petFrame: frame,
                bubbleFrame: nil,
                placement: placement,
                petAnchorInWindow: CGPoint(x: frame.midX, y: frame.midY)
            )
        }

        let horizontalGap = placement.isBubbleLeftOfPet ? leftBubbleGap : bubbleGap
        let topAdjustment = placement == .topLeft ? petVisualFrame : 0
        let bottomAdjustment = placement.isBubbleAbovePet ? 0 : petVisualFrame
        let containerSize = CGSize(
            width: petSize.width + horizontalGap + bubbleSize.width + windowGutter * 2,
            height: max(
                petSize.height,
                petSize.height + bubbleGap + bubbleSize.height
                    - topAdjustment - bottomAdjustment
            ) + windowGutter * 2
        )

        let petX: CGFloat
        let bubbleX: CGFloat
        if placement.isBubbleLeftOfPet {
            bubbleX = windowGutter
            petX = windowGutter + bubbleSize.width + horizontalGap
        } else {
            petX = windowGutter
            bubbleX = windowGutter + petSize.width + horizontalGap
        }

        let petY: CGFloat
        let bubbleY: CGFloat
        if placement.isBubbleAbovePet {
            bubbleY = windowGutter
            petY = max(windowGutter,
                       windowGutter + bubbleSize.height + bubbleGap - topAdjustment)
        } else {
            petY = windowGutter
            bubbleY = max(windowGutter,
                          windowGutter + petSize.height + bubbleGap - bottomAdjustment)
        }

        let petFrame = CGRect(origin: CGPoint(x: petX, y: petY), size: petSize)
        return AgentDetachedWindowLayout(
            containerSize: containerSize,
            petFrame: petFrame,
            bubbleFrame: CGRect(origin: CGPoint(x: bubbleX, y: bubbleY), size: bubbleSize),
            placement: placement,
            petAnchorInWindow: CGPoint(x: petFrame.midX, y: petFrame.midY)
        )
    }

    static func preferredPlacement(
        petScreenAnchor: CGPoint,
        bubbleSize: CGSize,
        availableFrame: CGRect,
        preferred: AgentDetachedBubblePlacement = .topLeft
    ) -> AgentDetachedBubblePlacement {
        var fallback = preferred
        var fallbackArea: CGFloat = -.greatestFiniteMagnitude
        for placement in AgentDetachedBubblePlacement.priorityOrder {
            let frame = bubbleScreenFrame(
                placement: placement,
                petScreenAnchor: petScreenAnchor,
                bubbleSize: bubbleSize
            )
            if availableFrame.contains(frame) { return placement }
            let intersection = frame.intersection(availableFrame)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            if area > fallbackArea {
                fallbackArea = area
                fallback = placement
            }
        }
        return fallback
    }

    private static func bubbleScreenFrame(
        placement: AgentDetachedBubblePlacement,
        petScreenAnchor: CGPoint,
        bubbleSize: CGSize
    ) -> CGRect {
        let petFrame = CGRect(
            x: petScreenAnchor.x - petHitFrame / 2,
            y: petScreenAnchor.y - petHitFrame / 2,
            width: petHitFrame,
            height: petHitFrame
        )
        let horizontalGap = placement.isBubbleLeftOfPet ? leftBubbleGap : bubbleGap
        return CGRect(
            x: placement.isBubbleLeftOfPet
                ? petFrame.minX - horizontalGap - bubbleSize.width
                : petFrame.maxX + horizontalGap,
            y: placement.isBubbleAbovePet
                ? petFrame.maxY + bubbleGap
                : petFrame.minY - bubbleGap - bubbleSize.height,
            width: bubbleSize.width,
            height: bubbleSize.height
        )
    }
}

enum AgentDetachedBubbleMode: Equatable {
    case hidden
    case hoverPreview
    case pinnedList

    var isVisible: Bool { self != .hidden }
}

enum AgentDetachedBubblePlacement: CaseIterable, Equatable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    static let priorityOrder: [Self] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    var isBubbleLeftOfPet: Bool {
        self == .topLeft || self == .bottomLeft
    }

    var isBubbleAbovePet: Bool {
        self == .topLeft || self == .topRight
    }
}

struct AgentDetachedWindowLayout: Equatable {
    let containerSize: CGSize
    let petFrame: CGRect
    let bubbleFrame: CGRect?
    let placement: AgentDetachedBubblePlacement
    let petAnchorInWindow: CGPoint
}

enum AgentIslandDetachmentGate {
    static let minimumPressDuration: TimeInterval = 0.35
    static let maximumPrepressMovement: CGFloat = 8
    static let minimumDownwardTranslation: CGFloat = 20

    static func accepts(_ translation: CGSize) -> Bool {
        translation.height >= minimumDownwardTranslation
            && translation.height > abs(translation.width)
    }
}

/// Exact pinned quadratic Island outline. Product identity, ownership, and
/// fullscreen behavior remain N1KO-specific.
struct AgentIslandShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY + topRadius),
            control: CGPoint(x: rect.minX + topRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + topRadius, y: rect.maxY - bottomRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + topRadius + bottomRadius, y: rect.maxY),
            control: CGPoint(x: rect.minX + topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius - bottomRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - topRadius, y: rect.maxY - bottomRadius),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY + topRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - topRadius, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return path
    }
}

enum AgentMascotStatus: Equatable {
    case idle
    case working
    case warning
    case dragging
}

/// Thin N1KO provider adapter over the complete pinned Ping-Island mascot
/// renderer. The drawings remain identical; settings and lifecycle ownership
/// stay inside N1KO-STATE.
struct AgentProviderMascot: View {
    @ObservedObject private var settings = AppSettings.shared
    let provider: AgentProvider
    let status: AgentMascotStatus
    var size: CGFloat = 18
    var animationTime: TimeInterval?

    var body: some View {
        AgentMascotView(
            kind: resolvedKind,
            status: status,
            size: size,
            animationTime: animationTime,
            isDragging: status == .dragging
        )
        .accessibilityHidden(true)
    }

    private var resolvedKind: AgentMascotKind {
        guard let override = settings.agentMascotOverrides[provider.rawValue],
              let kind = AgentMascotKind(rawValue: override) else {
            return AgentMascotKind(provider: provider)
        }
        return kind
    }
}

/// Kept for compatibility with older deterministic fixtures. Production views
/// now use `AgentProviderMascot`.
struct AgentPixelGlyph: View {
    let color: Color
    let isActive: Bool
    var size: CGFloat = 16

    private let pixels = [
        "..1111..",
        ".122221.",
        "12222221",
        "12W22W21",
        "12222221",
        ".12DD21.",
        "..1111..",
        "...11..."
    ]

    var body: some View {
        Canvas { context, canvasSize in
            let cell = floor(min(canvasSize.width, canvasSize.height) / 8)
            let origin = CGPoint(x: (canvasSize.width - cell * 8) / 2,
                                 y: (canvasSize.height - cell * 8) / 2)
            for (row, line) in pixels.enumerated() {
                for (column, symbol) in line.enumerated() where symbol != "." {
                    let fill: Color
                    switch symbol {
                    case "W": fill = .white.opacity(0.95)
                    case "D": fill = color.opacity(0.42)
                    case "1": fill = color.opacity(0.72)
                    default: fill = color
                    }
                    let pixel = CGRect(x: origin.x + CGFloat(column) * cell,
                                       y: origin.y + CGFloat(row) * cell,
                                       width: cell,
                                       height: cell)
                    context.fill(Path(pixel), with: .color(fill))
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(isActive ? 0.72 : 0.34), radius: isActive ? 4 : 2)
        .accessibilityHidden(true)
    }
}
