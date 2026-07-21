import Foundation
import N1KOAgentCore
import SwiftUI

// N1KO modification notice:
// The opened routes, interaction hierarchy, measured-height behavior, and
// floating Buddy presentation in this file are adapted from Apache-2.0 Ping
// Island commit da130d6. N1KO retains its own data, response, and window owners.

private struct AgentOpenedContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    func reportAgentOpenedContentHeight(additionalHeight: CGFloat = 0) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: AgentOpenedContentHeightPreferenceKey.self,
                    value: geometry.size.height + additionalHeight
                )
            }
        )
    }
}

enum AgentSurfaceKind: Equatable {
    case desktop
    case fullscreenReveal
}

struct AgentIslandRootView: View {
    @ObservedObject var model: AgentSurfaceModel
    let surface: AgentSurfaceKind
    let onResponse: (AgentSurfaceResponseRequest) -> Void
    let onOpenAgentCenter: () -> Void
    let onDismiss: () -> Void
    let onHoverChanged: (Bool) -> Void
    let onSessionAction: (AgentSessionSurfaceAction) -> Void
    let onDetach: () -> Void
    let onFollowUp: (AgentSessionSnapshot, String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var settings = AppSettings.shared
    @State private var isHovering = false

    init(
        model: AgentSurfaceModel,
        surface: AgentSurfaceKind,
        onResponse: @escaping (AgentSurfaceResponseRequest) -> Void,
        onOpenAgentCenter: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onHoverChanged: @escaping (Bool) -> Void,
        onSessionAction: @escaping (AgentSessionSurfaceAction) -> Void = { _ in },
        onDetach: @escaping () -> Void = {},
        onFollowUp: @escaping (AgentSessionSnapshot, String) -> Void = { _, _ in }
    ) {
        self.model = model
        self.surface = surface
        self.onResponse = onResponse
        self.onOpenAgentCenter = onOpenAgentCenter
        self.onDismiss = onDismiss
        self.onHoverChanged = onHoverChanged
        self.onSessionAction = onSessionAction
        self.onDetach = onDetach
        self.onFollowUp = onFollowUp
    }

    private var isOpen: Bool { surface == .fullscreenReveal || model.isExpanded }
    private var topRadius: CGFloat {
        isOpen ? AgentIslandLayout.openTopRadius : AgentIslandLayout.closedTopRadius
    }
    private var bottomRadius: CGFloat {
        isOpen ? AgentIslandLayout.openBottomRadius : AgentIslandLayout.closedBottomRadius
    }

    var body: some View {
        Group {
            if isOpen {
                expanded
            } else {
                compact
            }
        }
        .background(Color.black)
        .clipShape(AgentIslandShape(topRadius: topRadius, bottomRadius: bottomRadius))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.black)
                .frame(height: 1)
                .padding(.horizontal, topRadius)
        }
        .shadow(color: isOpen || isHovering ? Color.black.opacity(0.70) : .clear, radius: 6)
        .contentShape(Rectangle())
        .onHover(perform: handleHover)
        .onDisappear { onHoverChanged(false) }
        .animation(islandAnimation, value: model.isExpanded)
        .animation(islandAnimation, value: model.expansionTrigger)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent Island".loc)
        .onPreferenceChange(AgentOpenedContentHeightPreferenceKey.self) { height in
            guard isOpen,
                  case .conversation = model.route(for: surface) else {
                DispatchQueue.main.async {
                    model.updateOpenedMeasuredContentHeight(height > 0 ? height : nil)
                }
                return
            }
            // Chat uses Ping Island's fixed large panel and must not inherit a
            // stale natural-height measurement from another route.
            DispatchQueue.main.async { model.updateOpenedMeasuredContentHeight(nil) }
        }
        .simultaneousGesture(
            LongPressGesture(
                minimumDuration: AgentIslandDetachmentGate.minimumPressDuration,
                maximumDistance: AgentIslandDetachmentGate.maximumPrepressMovement
            )
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onEnded { value in
                    guard surface == .desktop,
                          case .second(true, let drag?) = value,
                          AgentIslandDetachmentGate.accepts(drag.translation) else { return }
                    onDetach()
                }
        )
    }

    private var compact: some View {
        Button {
            model.expand(reason: .click)
        } label: {
            HStack(spacing: 0) {
                AgentProviderMascot(
                    provider: model.projection.primarySession?.provider ?? .codex,
                    status: compactMascotStatus,
                    size: 16
                )
                    .frame(width: 34)

                Text(compactMessage)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(model.projection.primarySession == nil ? 0.42 : 0.82))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.84)
                    .frame(maxWidth: .infinity, alignment: .center)

                compactTrailing
                    .frame(width: 34, alignment: .center)
            }
            .padding(.horizontal, AgentIslandLayout.closedBottomRadius)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(N1KOButtonStyle())
        .accessibilityLabel(compactAccessibilityLabel)
        .accessibilityHint("Expands Agent Island details.".loc)
    }

    @ViewBuilder
    private var compactTrailing: some View {
        if model.projection.attentionCount > 0 {
            Image(systemName: "bell.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Theme.warn)
                .accessibilityLabel("Needs attention".loc)
        } else if model.projection.activeCount > 0 {
            Text("\(model.projection.activeCount)")
                .font(.system(size: model.projection.activeCount >= 10 ? 8.8 : 9.6,
                              weight: .semibold,
                              design: .monospaced))
                .tracking(model.projection.activeCount >= 10 ? -0.15 : -0.05)
                .foregroundColor(.white.opacity(0.92))
                .frame(minWidth: 18)
                .offset(x: 4)
                .accessibilityLabel("\("Sessions".loc), \(model.projection.activeCount)")
        } else {
            Color.clear.frame(width: 16, height: 16)
        }
    }

    private var expanded: some View {
        VStack(spacing: 0) {
            expandedHeader
                .frame(height: 32)
                .padding(.horizontal, 18)

            routeContent
        }
    }

    private var expandedHeader: some View {
        HStack(spacing: 8) {
            if settings.agentShowUsage
                && (model.projection.usage.totalTokens > 0
                    || !model.projection.usageWindows.isEmpty) {
                AgentHeaderUsageStrip(
                    usage: model.projection.usage,
                    windowsByProvider: model.projection.usageWindows
                )
            }

            Spacer(minLength: 0)

            AgentHeaderSquareButton(
                systemImage: settings.agentNotificationsTemporarilyMuted
                    ? "speaker.slash.fill" : "speaker.wave.2.fill",
                isActive: settings.agentNotificationsTemporarilyMuted,
                help: settings.agentNotificationsTemporarilyMuted
                    ? "Resume Agent notifications".loc
                    : "Mute Agent notifications for 10 minutes".loc,
                action: { settings.toggleAgentNotificationMute() }
            )

            AgentHeaderSquareButton(
                systemImage: "gearshape.fill",
                isActive: false,
                help: "Open Agent Center settings".loc,
                action: onOpenAgentCenter
            )

        }
    }

    @ViewBuilder
    private var routeContent: some View {
        switch model.route(for: surface) {
        case .sessionList:
            AgentSessionListSurface(
                sessions: model.projection.sessions,
                selectedIndex: model.selectedSessionIndex,
                onSelect: model.openConversation,
                onAction: onSessionAction
            )
        case .hoverDashboard:
            AgentHoverDashboardSurface(
                sessions: Array(model.projection.sessions.prefix(3)),
                onOpen: model.openConversation
            )
        case .attention(let id):
            if let session = model.session(id: id), let intervention = session.intervention {
                ScrollView(.vertical, showsIndicators: true) {
                    AgentInterventionSurface(session: session,
                                             intervention: intervention,
                                             onResponse: onResponse)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 18)
                    .reportAgentOpenedContentHeight()
                }
                .onHover(perform: model.setNotificationHovered)
                .onDisappear { model.setNotificationHovered(false) }
            } else if let session = model.session(id: id) {
                AgentHoverDashboardSurface(sessions: [session], onOpen: model.openConversation)
            }
        case .completion(let id):
            if let session = model.session(id: id) {
                AgentCompletionSurface(
                    session: session,
                    onHoverChanged: model.setNotificationHovered,
                    onDismiss: { model.dismissNotification(keepOpen: false) }
                )
                .reportAgentOpenedContentHeight()
            }
        case .conversation(let id):
            if let session = model.session(id: id) {
                AgentConversationSurface(session: session,
                                         onBack: model.showSessionList,
                                         onFollowUp: { onFollowUp(session, $0) })
            }
        }

        if let responseStatus = model.responseStatus {
            Text(responseStatus)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.50))
                .padding(.horizontal, 18)
                .padding(.bottom, 8)
        }
    }

    private var recentCompletion: AgentSessionSnapshot? {
        model.projection.sessions.first(where: { $0.phase == .completed })
    }

    private var compactMessage: String {
        guard let session = model.projection.primarySession else { return "" }
        if let preview = session.preview?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preview.isEmpty {
            return preview
        }
        return session.title
    }

    private var primaryColor: Color {
        model.projection.primarySession?.provider.presentationColor ?? Color.white.opacity(0.34)
    }

    private var compactMascotStatus: AgentMascotStatus {
        guard let session = model.projection.primarySession else { return .idle }
        if session.needsAttention { return .warning }
        if session.phase == .processing || session.phase == .starting { return .working }
        return .idle
    }

    private var compactAccessibilityLabel: String {
        guard let session = model.projection.primarySession else {
            return "Agent Center, no active sessions".loc
        }
        return "Agent session %@, %@".locf(session.title, session.phase.presentationTitle)
    }

    private var islandAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: AgentIslandLayout.reducedTransitionDuration)
            : .spring(response: 0.42, dampingFraction: 0.82, blendDuration: 0)
    }

    private func handleHover(_ hovering: Bool) {
        isHovering = hovering
        if surface == .desktop { onHoverChanged(hovering) }
    }

    private func closeExpanded() {
        if surface == .fullscreenReveal {
            onDismiss()
        } else {
            model.collapse()
        }
    }
}

struct AgentDetachedIslandView: View {
    @ObservedObject var model: AgentSurfaceModel
    let onResponse: (AgentSurfaceResponseRequest) -> Void
    let onOpenAgentCenter: () -> Void
    let onReattach: () -> Void
    let onModeChanged: (AgentDetachedBubbleMode) -> Void
    let onSessionAction: (AgentSessionSurfaceAction) -> Void
    let onFollowUp: (AgentSessionSnapshot, String) -> Void

    @State private var mode: AgentDetachedBubbleMode = .hidden
    @State private var isHovering = false
    @ObservedObject private var settings = AppSettings.shared

    init(
        model: AgentSurfaceModel,
        onResponse: @escaping (AgentSurfaceResponseRequest) -> Void,
        onOpenAgentCenter: @escaping () -> Void,
        onReattach: @escaping () -> Void,
        onModeChanged: @escaping (AgentDetachedBubbleMode) -> Void,
        onSessionAction: @escaping (AgentSessionSurfaceAction) -> Void,
        initiallyExpanded: Bool = false,
        onFollowUp: @escaping (AgentSessionSnapshot, String) -> Void = { _, _ in }
    ) {
        self.model = model
        self.onResponse = onResponse
        self.onOpenAgentCenter = onOpenAgentCenter
        self.onReattach = onReattach
        self.onModeChanged = onModeChanged
        self.onSessionAction = onSessionAction
        self.onFollowUp = onFollowUp
        _mode = State(initialValue: initiallyExpanded ? .pinnedList : .hidden)
    }

    var body: some View {
        let layout = detachedLayout
        ZStack(alignment: .topLeading) {
            if let bubbleFrame = layout.bubbleFrame {
                VStack(alignment: .leading, spacing: settings.agentShowUsage ? 4 : 8) {
                    detachedContent

                    if settings.agentShowUsage
                        && (model.projection.usage.totalTokens > 0
                            || !model.projection.usageWindows.isEmpty) {
                        HStack {
                            Spacer(minLength: 0)
                            AgentHeaderUsageStrip(
                                usage: model.projection.usage,
                                windowsByProvider: model.projection.usageWindows
                            )
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                    }
                }
                .frame(width: bubbleFrame.width,
                       height: bubbleFrame.height,
                       alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.black)
                )
                .shadow(color: .black.opacity(0.50), radius: 12, y: 6)
                .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .bottomTrailing)))
                .offset(x: bubbleFrame.minX, y: bubbleFrame.minY)
            }

            ZStack(alignment: .bottomTrailing) {
                let renderSize = AgentDetachedIslandLayout.mascotDisplaySize
                    * AgentDetachedIslandLayout.mascotRenderScale
                AgentProviderMascot(
                    provider: model.projection.primarySession?.provider ?? .codex,
                    status: model.projection.primarySession?.mascotStatus ?? .idle,
                    size: renderSize
                )
                .frame(width: renderSize, height: renderSize)
                .scaleEffect(AgentDetachedIslandLayout.mascotDisplaySize / renderSize)
                .frame(width: AgentDetachedIslandLayout.mascotDisplaySize,
                       height: AgentDetachedIslandLayout.mascotDisplaySize)
                .frame(width: AgentDetachedIslandLayout.petVisualFrame,
                       height: AgentDetachedIslandLayout.petVisualFrame)

                if model.projection.activeCount > 0 {
                    Text("\(model.projection.activeCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.88))
                        .shadow(color: .black.opacity(0.9), radius: 2)
                        .accessibilityLabel("\("Sessions".loc), \(model.projection.activeCount)")
                        .offset(x: -6, y: -10)
                }
            }
            .frame(width: layout.petFrame.width,
                   height: layout.petFrame.height)
            .offset(x: layout.petFrame.minX, y: layout.petFrame.minY)
            .contentShape(Rectangle())
            .onTapGesture {
                mode = mode == .pinnedList ? .hidden : .pinnedList
                onModeChanged(mode)
            }
            .contextMenu {
                Button("Open Agent Center".loc, action: onOpenAgentCenter)
                Button("Reattach to Island".loc, action: onReattach)
            }
            .help("Drag to move. Hover to expand; right-click for options.".loc)
        }
        .frame(width: layout.containerSize.width,
               height: layout.containerSize.height,
               alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover(perform: handleHover)
        .onChange(of: model.notificationSessionID) { notificationID in
            guard notificationID != nil, mode != .pinnedList else { return }
            mode = .hoverPreview
            onModeChanged(mode)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.84), value: mode)
        .preferredColorScheme(.dark)
    }

    private var detachedRoute: AgentIslandRoute {
        model.detachedRoute(for: mode)
    }

    private var detachedLayout: AgentDetachedWindowLayout {
        AgentDetachedIslandLayout.windowLayout(
            bubbleSize: mode.isVisible
                ? AgentDetachedIslandLayout.bubbleSize(
                    route: detachedRoute,
                    projection: model.projection
                )
                : nil,
            placement: model.detachedBubblePlacement
        )
    }

    @ViewBuilder
    private var detachedContent: some View {
        switch detachedRoute {
        case .attention(let id):
            if let session = model.session(id: id), let intervention = session.intervention {
                ScrollView(.vertical, showsIndicators: true) {
                    AgentInterventionSurface(session: session,
                                             intervention: intervention,
                                             onResponse: onResponse)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }
        case .completion(let id):
            if let session = model.session(id: id) {
                AgentCompletionSurface(
                    session: session,
                    onHoverChanged: model.setNotificationHovered,
                    onDismiss: { model.dismissNotification() }
                )
            }
        case .conversation(let id):
            if let session = model.session(id: id) {
                AgentConversationSurface(session: session,
                                         onBack: model.showSessionList,
                                         onFollowUp: { onFollowUp(session, $0) })
            }
        case .sessionList:
            AgentSessionListSurface(
                sessions: model.projection.sessions,
                selectedIndex: model.selectedSessionIndex,
                onSelect: model.openConversation,
                onAction: onSessionAction
            )
        case .hoverDashboard:
            AgentHoverDashboardSurface(sessions: Array(model.projection.sessions.prefix(2)),
                                       onOpen: model.openConversation)
        }
    }

    private func handleHover(_ hovering: Bool) {
        isHovering = hovering
        if hovering {
            guard mode == .hidden else { return }
            mode = .hoverPreview
            onModeChanged(mode)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                guard !isHovering, mode == .hoverPreview else { return }
                mode = .hidden
                onModeChanged(mode)
            }
        }
    }
}

private struct AgentMetadataBadge: View {
    let text: String
    var systemImage: String?
    let color: Color

    init(text: String, systemImage: String? = nil, color: Color) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 7.5, weight: .semibold))
            }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(Capsule().fill(color.opacity(0.12)))
        .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 0.5))
    }
}

private struct AgentHeaderSquareButton: View {
    let systemImage: String
    let isActive: Bool
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(isHovering && !isActive ? .black : .white.opacity(isActive ? 0.60 : 0.92))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isHovering && !isActive
                              ? Color.white.opacity(0.95)
                              : Color.white.opacity(isActive ? 0.06 : 0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(isActive ? 0.12 : 0), lineWidth: 1)
                )
        }
        .buttonStyle(N1KOButtonStyle())
        .help(help)
        .accessibilityLabel(help)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
    }
}

private struct AgentInterventionSurface: View {
    let session: AgentSessionSnapshot
    let intervention: AgentIntervention
    let onResponse: (AgentSurfaceResponseRequest) -> Void
    @State private var optionAnswers: [String: Set<String>] = [:]
    @State private var textAnswers: [String: String] = [:]
    @State private var fallbackAnswer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sessionHeader
            if intervention.kind == .approval {
                approvalContent
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(intervention.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    if let message = intervention.message, !message.isEmpty {
                        Text(message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if intervention.questions.isEmpty {
                    answerField("Type an answer".loc, text: $fallbackAnswer)
                } else {
                    ForEach(intervention.questions, id: \.id) { question in
                        questionView(question)
                    }
                }
                interventionButton("Send Answer".loc) {
                    send(.answer(collectedAnswers))
                }
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(interventionAccent.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(interventionAccent.opacity(0.26), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent intervention for %@".locf(session.title))
    }

    private var sessionHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .topTrailing) {
                AgentProviderMascot(provider: session.provider,
                                    status: .warning,
                                    size: 18,
                                    animationTime: 0)
                    .frame(width: 26, height: 26)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Image(systemName: intervention.kind == .approval
                      ? "exclamationmark.circle.fill" : "questionmark.circle.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(interventionAccent)
                    .offset(x: 2, y: -2)
            }

            VStack(alignment: .leading, spacing: 5) {
                (Text(session.projectName)
                    .foregroundColor(.white.opacity(0.88))
                 + Text(" · ").foregroundColor(.white.opacity(0.42))
                 + Text(session.title).foregroundColor(.white))
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    AgentMetadataBadge(text: session.relativeTime,
                                       color: .white.opacity(0.72))
                    AgentMetadataBadge(text: session.provider.presentationTitle,
                                       color: session.provider.presentationColor)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var approvalContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("%@ requests approval".locf(session.provider.presentationTitle))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                Text((intervention.toolName?.isEmpty == false
                      ? intervention.toolName! : "Current action".loc))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.orange.opacity(0.95))

                Text(intervention.message?.isEmpty == false
                     ? intervention.message! : "Approval continues the current session.".loc)
                    .font(.system(size: 11, weight: .medium,
                                  design: intervention.toolName == nil ? .default : .monospaced))
                    .foregroundColor(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 8) {
                approvalButton("Deny".loc,
                               background: Color.white.opacity(0.10)) {
                    send(.deny(reason: nil))
                }
                approvalButton("Approve for session".loc,
                               background: Color.blue.opacity(0.26)) {
                    send(.approve(scope: "session"))
                }
                approvalButton("Approve".loc,
                               background: Color.white.opacity(0.92),
                               foreground: .black) {
                    send(.approve(scope: nil))
                }
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func questionView(_ question: AgentQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header = question.header, !header.isEmpty {
                HStack(spacing: 8) {
                    Text(header)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.blue.opacity(0.90))
                    if question.allowsMultiple {
                        Text("Multiple".loc)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.orange.opacity(0.95))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.14))
                            .clipShape(Capsule())
                    }
                }
            }
            Text(question.prompt)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
            if !question.options.isEmpty {
                let reservesDetailSpace = question.options.contains {
                    $0.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                }
                LazyVGrid(columns: optionColumns(for: question), spacing: 8) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                        let selected = isSelected(option.label, for: question)
                        Button {
                            toggle(option.label, for: question)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text(Self.optionSequenceLabel(for: index))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(selected ? Color.blue : .white.opacity(0.62))
                                    .frame(width: 20, height: 20)
                                    .background(Circle().fill(selected
                                        ? Color.blue.opacity(0.16) : Color.white.opacity(0.06)))

                                if question.allowsMultiple {
                                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(selected ? Color.blue : .white.opacity(0.55))
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(option.label)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let description = option.description,
                                       !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text(description)
                                            .font(.system(size: 10))
                                            .foregroundColor(.white.opacity(0.55))
                                            .fixedSize(horizontal: false, vertical: true)
                                    } else if reservesDetailSpace {
                                        Text(" ").font(.system(size: 10)).hidden()
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(selected ? Color.blue.opacity(0.12) : Color.white.opacity(0.04)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(selected ? Color.blue.opacity(0.72)
                                    : Color.white.opacity(0.14), lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(N1KOButtonStyle())
                    }
                }
            }
            if question.allowsOther || question.options.isEmpty {
                answerField("Type an answer".loc, text: Binding(
                    get: { textAnswers[question.id, default: ""] },
                    set: { textAnswers[question.id] = $0 }
                ))
            }
        }
    }

    private func optionColumns(for question: AgentQuestion) -> [GridItem] {
        if question.options.count == 4 {
            return [
                GridItem(.flexible(minimum: 0), spacing: 8),
                GridItem(.flexible(minimum: 0), spacing: 8)
            ]
        }
        if question.options.contains(where: {
            $0.label.count > 24 || ($0.description?.count ?? 0) > 72
        }) {
            return [GridItem(.flexible(minimum: 0), spacing: 8)]
        }
        return [GridItem(.adaptive(minimum: 150), spacing: 8)]
    }

    private static func optionSequenceLabel(for index: Int) -> String {
        guard index >= 0 else { return "" }
        var remaining = index
        var label = ""
        repeat {
            if let scalar = UnicodeScalar(65 + remaining % 26) {
                label.insert(Character(scalar), at: label.startIndex)
            }
            remaining = remaining / 26 - 1
        } while remaining >= 0
        return label
    }

    private func answerField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.white.opacity(0.90))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )
            )
    }

    private func interventionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(Capsule().fill(Color.white.opacity(0.90)))
        }
        .buttonStyle(N1KOButtonStyle())
    }

    private var interventionAccent: Color {
        intervention.kind == .question
            ? Color(red: 0.33, green: 0.67, blue: 1.0)
            : Color(red: 1.0, green: 0.66, blue: 0.18)
    }

    private func approvalButton(
        _ title: String,
        background: Color,
        foreground: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(background))
        }
        .buttonStyle(N1KOButtonStyle())
    }

    private var canSubmit: Bool {
        if intervention.questions.isEmpty {
            return !fallbackAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !intervention.questions.contains {
            collectedAnswers[$0.id, default: []].isEmpty
        }
    }

    private var collectedAnswers: [String: [String]] {
        if intervention.questions.isEmpty {
            let text = fallbackAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
            return ["answer": text.isEmpty ? [] : [text]]
        }
        return Dictionary(uniqueKeysWithValues: intervention.questions.map { question in
            var values = Array(optionAnswers[question.id, default: []]).sorted()
            let text = textAnswers[question.id, default: ""]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { values.append(text) }
            return (question.id, values)
        })
    }

    private func isSelected(_ label: String, for question: AgentQuestion) -> Bool {
        optionAnswers[question.id, default: []].contains(label)
    }

    private func toggle(_ label: String, for question: AgentQuestion) {
        if question.allowsMultiple {
            if optionAnswers[question.id, default: []].contains(label) {
                optionAnswers[question.id]?.remove(label)
            } else {
                optionAnswers[question.id, default: []].insert(label)
            }
        } else {
            optionAnswers[question.id] = [label]
        }
    }

    private func send(_ action: AgentResponseAction) {
        onResponse(AgentSurfaceResponseRequest(
            provider: session.provider,
            sessionID: session.sessionID,
            requestID: intervention.requestID,
            ownerID: intervention.responseOwnerID,
            capability: intervention.responseCapability,
            action: action
        ))
    }
}

private struct AgentCompletionSurface: View {
    let session: AgentSessionSnapshot
    let onHoverChanged: (Bool) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AgentProviderMascot(provider: session.provider, status: .idle, size: 18)
                Text(session.projectName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.82))
                Text("·").foregroundColor(.white.opacity(0.34))
                Text(session.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Spacer()
                AgentMetadataBadge(text: "Completed".loc, color: Theme.ok)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Text("You".loc + ":")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.44))
                    Text(session.latestUserText ?? session.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white.opacity(0.86))
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(session.relativeTime)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.38))
                }
                .padding(14)

                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

                HStack(alignment: .top, spacing: 10) {
                    Text(session.provider.presentationTitle + ":")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(session.provider.presentationColor.opacity(0.92))
                    Text(session.latestAssistantText ?? "The session completed successfully.".loc)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.80))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.06)))
            )
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .contentShape(Rectangle())
        .onHover(perform: onHoverChanged)
        .onDisappear { onHoverChanged(false) }
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Completed agent session %@".locf(session.title))
    }
}

private struct AgentSessionListSurface: View {
    let sessions: [AgentSessionSnapshot]
    let selectedIndex: Int
    let onSelect: (AgentSessionSnapshot) -> Void
    let onAction: (AgentSessionSurfaceAction) -> Void
    @State private var expandedSessionID: String?

    private var groups: [(AgentSessionSnapshot, [AgentSessionSnapshot])] {
        let parents = sessions.filter { $0.parentSessionID == nil }
        let roots = parents.isEmpty ? sessions : parents
        return roots.map { parent in
            (parent, sessions.filter { $0.parentSessionID == parent.sessionID })
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: sessions.count > 3) {
            if sessions.isEmpty {
                VStack(spacing: 6) {
                    AgentProviderMascot(provider: .codex, status: .idle, size: 26, animationTime: 0)
                    Text("No sessions".loc)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.40))
                    Text("Run a supported coding agent to begin.".loc)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.25))
                }
                .frame(maxWidth: .infinity, minHeight: 110)
                .reportAgentOpenedContentHeight(additionalHeight: 17)
            } else {
                LazyVStack(spacing: 2) {
                    ForEach(Array(groups.enumerated()), id: \.element.0.id) { _, group in
                        AgentSessionRow(
                            session: group.0,
                            isExpanded: expandedSessionID == group.0.id,
                            isSelected: sessions.indices.contains(selectedIndex)
                                && sessions[selectedIndex].id == group.0.id,
                            onToggle: {
                                expandedSessionID = expandedSessionID == group.0.id ? nil : group.0.id
                            },
                            onOpen: { onSelect(group.0) },
                            onAction: onAction
                        )

                        ForEach(group.1) { child in
                            AgentSubagentRow(session: child) { onSelect(child) }
                                .padding(.leading, 44)
                        }
                    }
                }
                .reportAgentOpenedContentHeight(additionalHeight: 17)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 5)
        .padding(.bottom, 12)
    }
}

private struct AgentSessionRow: View {
    let session: AgentSessionSnapshot
    let isExpanded: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onAction: (AgentSessionSurfaceAction) -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    AgentProviderMascot(provider: session.provider,
                                        status: session.mascotStatus,
                                        size: 18)
                    Circle()
                        .fill(session.phase.presentationColor)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                        .opacity(session.phase.isTerminal ? 0 : 1)
                        .offset(x: 1, y: 1)
                }
                .frame(width: 34, height: 34)

                Button {
                    if session.phase.isTerminal {
                        onToggle()
                    } else {
                        onAction(.focus(session))
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        (Text(session.projectName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.84))
                         + Text(" · ")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white.opacity(0.34))
                         + Text(session.title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white))
                            .lineLimit(1)

                        if isExpanded || !session.phase.isTerminal {
                            Text(session.previewText)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white.opacity(0.48))
                                .lineLimit(isExpanded ? 2 : 1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(N1KOButtonStyle())

                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        AgentMetadataBadge(text: session.relativeTime,
                                           color: .white.opacity(0.56))
                        AgentMetadataBadge(text: session.provider.presentationTitle,
                                           color: session.provider.presentationColor)
                    }

                    HStack(spacing: 6) {
                        iconButton("bubble.left", help: "Open conversation".loc, action: onOpen)
                        if session.phase.isTerminal {
                            iconButton("archivebox", help: "Archive".loc) {
                                onAction(.archive(session))
                            }
                        }
                    }
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 8)

            if isExpanded && session.phase.isTerminal {
                HStack(spacing: 5) {
                    actionButton("Focus".loc, icon: "scope") { onAction(.focus(session)) }
                    actionButton("Archive".loc, icon: "archivebox") { onAction(.archive(session)) }
                    Spacer(minLength: 0)
                }
                .padding(.leading, 54)
                .padding(.trailing, 12)
                .padding(.bottom, 8)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(isHovered || isSelected ? 0.065 : 0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(session.needsAttention
                                ? session.phase.presentationColor.opacity(0.40)
                                : Color.white.opacity(isSelected ? 0.12 : 0.05), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("%@, %@, %@".locf(
            session.title, session.provider.presentationTitle,
            session.phase.presentationTitle
        ))
    }

    private func actionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(.white.opacity(0.62))
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(N1KOButtonStyle())
    }

    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(isHovered ? 0.80 : 0.42))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.white.opacity(0.10) : Color.clear))
        }
        .buttonStyle(N1KOButtonStyle())
        .help(help)
    }
}

private struct AgentSubagentRow: View {
    let session: AgentSessionSnapshot
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 8) {
                AgentProviderMascot(provider: session.provider,
                                    status: session.mascotStatus,
                                    size: 14,
                                    animationTime: 0)
                Text(session.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(.white.opacity(0.74))
                    .lineLimit(1)
                Spacer()
                Text(session.relativeTime)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.34))
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.025)))
        }
        .buttonStyle(N1KOButtonStyle())
    }
}

private struct AgentHoverDashboardSurface: View {
    let sessions: [AgentSessionSnapshot]
    let onOpen: (AgentSessionSnapshot) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                if sessions.isEmpty {
                    VStack(spacing: 8) {
                        AgentProviderMascot(provider: .codex, status: .idle, size: 28)
                        Text("No active sessions".loc)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.40))
                        Text("Hover here while an agent is working to preview its latest conversation.".loc)
                            .font(.system(size: 10.5))
                            .foregroundColor(.white.opacity(0.26))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96)
                }

                ForEach(sessions) { session in
                    AgentHoverSessionRow(session: session) { onOpen(session) }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 7)
            .padding(.bottom, 12)
            .reportAgentOpenedContentHeight()
        }
    }
}

private struct AgentHoverSessionRow: View {
    let session: AgentSessionSnapshot
    let onOpen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                AgentProviderMascot(provider: session.provider,
                                    status: session.mascotStatus,
                                    size: 24)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    (Text(session.projectName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.86))
                     + Text(" · ")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.34))
                     + Text(session.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white))
                        .lineLimit(1)

                    if let user = session.latestUserText {
                        (Text("You: ").foregroundColor(.white.opacity(0.42))
                         + Text(user).foregroundColor(.white.opacity(0.68)))
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                    }

                    (Text(session.phase == .processing ? "Working: " : "Latest: ")
                        .foregroundColor(session.provider.presentationColor.opacity(0.76))
                     + Text(session.latestAssistantText ?? session.previewText)
                        .foregroundColor(.white.opacity(0.52)))
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(3)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    AgentMetadataBadge(text: session.relativeTime,
                                       color: .white.opacity(0.55))
                    AgentMetadataBadge(text: session.provider.presentationTitle,
                                       color: session.provider.presentationColor)
                    if session.needsAttention {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(session.phase.presentationColor)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(session.phase.presentationColor.opacity(0.10)))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.06 : 0.025))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(session.needsAttention
                                    ? session.phase.presentationColor.opacity(0.30)
                                    : Color.white.opacity(0.045))
                    )
            )
        }
        .buttonStyle(N1KOButtonStyle())
        .onHover { isHovered = $0 }
    }
}

private struct AgentConversationSurface: View {
    let session: AgentSessionSnapshot
    let onBack: () -> Void
    let onFollowUp: (String) -> Void
    @State private var isHeaderHovered = false
    @State private var followUpText = ""

    private var recentItems: [AgentConversationItem] {
        let visible = session.conversationItems.filter { item in
            if session.provider == .codex {
                // Pinned Ping-Island's Codex inspector intentionally keeps
                // tool rows out of the compact transcript.
                return item.kind == .user || item.kind == .assistant || item.kind == .status
            }
            return true
        }
        return Array(visible.suffix(session.provider == .codex ? 6 : 12))
    }

    private var primaryResultText: String? {
        session.latestAssistantText ?? session.preview
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                Button(action: onBack) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Session List".loc)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(isHeaderHovered ? 1.0 : 0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isHeaderHovered ? Color.white.opacity(0.08) : Color.clear)
                    )
                }
                .buttonStyle(N1KOButtonStyle())
                .onHover { isHeaderHovered = $0 }
                .padding(.horizontal, 4)
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text(session.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        AgentMetadataBadge(text: session.provider.presentationTitle,
                                           color: session.provider.presentationColor)
                        AgentMetadataBadge(text: session.phase.presentationTitle,
                                           color: session.phase.presentationColor)
                        Text(session.relativeTime)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Text(session.previewText)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.72))
                        .lineLimit(3)

                    if let cwd = session.cwd, !cwd.isEmpty, cwd != "/" {
                        Text(cwd)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Text("Latest thread result".loc)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer(minLength: 0)

                        Text(session.phase.presentationTitle)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(session.phase.presentationColor.opacity(0.9))
                    }

                    if let primaryResultText, !primaryResultText.isEmpty {
                        renderedMarkdown(primaryResultText)
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("No thread details yet. Once the agent responds, the latest result will show here.".loc)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.56))
                    }

                    if !recentItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(recentItems) { item in
                                AgentConversationItemView(item: item,
                                                          providerColor: session.provider.presentationColor)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )

                if canSendFollowUp {
                    followUpComposer
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
    }

    private func renderedMarkdown(_ text: String) -> Text {
        guard let attributed = try? AttributedString(markdown: text) else {
            return Text(text)
        }
        return Text(attributed)
    }

    private var canSendFollowUp: Bool {
        AppSettings.shared.agentTMUXEnabled && session.navigation?.tmuxTarget != nil
    }

    private var followUpComposer: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if followUpText.isEmpty {
                    Text("Message %@...".locf(session.provider.presentationTitle))
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.34))
                        .allowsHitTesting(false)
                }

                TextField("", text: $followUpText)
            }
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.10))
                        )
                )
                .onSubmit(sendFollowUp)

            Button(action: sendFollowUp) {
                ZStack {
                    Circle()
                        .fill(trimmedFollowUp.isEmpty
                              ? Color.white.opacity(0.12)
                              : Color.white.opacity(0.90))
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(trimmedFollowUp.isEmpty
                                         ? .white.opacity(0.42)
                                         : .black.opacity(0.88))
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(N1KOButtonStyle())
            .disabled(trimmedFollowUp.isEmpty)
        }
        .padding(.horizontal, 2)
    }

    private var trimmedFollowUp: String {
        followUpText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendFollowUp() {
        let message = trimmedFollowUp
        guard !message.isEmpty else { return }
        followUpText = ""
        onFollowUp(message)
    }
}

private struct AgentConversationItemView: View {
    let item: AgentConversationItem
    let providerColor: Color

    @ViewBuilder
    var body: some View {
        if item.kind == .tool {
            AgentToolConversationItemView(item: item, providerColor: providerColor)
        } else {
            HStack(alignment: .top, spacing: 8) {
                Text(prefix)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(prefixColor)
                    .frame(width: 18, alignment: .leading)
                    .padding(.top, 2)

                renderedText
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(item.kind == .status ? 0.58 : 0.78))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
        }
    }

    private var renderedText: Text {
        guard let attributed = try? AttributedString(markdown: item.text) else {
            return Text(item.text)
        }
        return Text(attributed)
    }

    private var prefix: String {
        switch item.kind {
        case .user: return "Y"
        case .assistant: return "A"
        case .status: return "N"
        case .attention: return "!"
        case .tool: return ""
        }
    }

    private var prefixColor: Color {
        switch item.kind {
        case .assistant: return .white
        case .status: return providerColor.opacity(0.9)
        case .user: return .white.opacity(0.72)
        case .attention: return Theme.warn
        case .tool: return .clear
        }
    }
}

private struct AgentToolConversationItemView: View {
    let item: AgentConversationItem
    let providerColor: Color

    private var status: AgentToolStatus { item.toolStatus ?? .running }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: status.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(status.color(providerColor: providerColor))

                Text(formattedToolName)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.84))
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(status.title.loc)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(status.color(providerColor: providerColor).opacity(0.9))
            }

            if let input = item.toolInput, !input.isEmpty {
                toolPayload(label: "Input".loc, text: input, tint: providerColor)
            }

            if let result = item.toolResult, !result.isEmpty {
                toolPayload(label: "Result".loc,
                            text: result,
                            tint: status == .failed ? Theme.danger : Theme.ok)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(status.color(providerColor: providerColor).opacity(0.18))
                )
        )
    }

    private func toolPayload(label: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(tint.opacity(0.78))
            Text(text)
                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.68))
                .lineLimit(8)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var formattedToolName: String {
        let raw = item.toolName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return "Tool".loc }
        return raw
            .replacingOccurrences(of: "mcp__", with: "")
            .replacingOccurrences(of: "__", with: " · ")
            .replacingOccurrences(of: "_", with: " ")
    }
}

private extension AgentToolStatus {
    var title: String {
        switch self {
        case .running: return "Running"
        case .waitingForApproval: return "Waiting"
        case .completed: return "Done"
        case .failed: return "Failed"
        }
    }

    var symbolName: String {
        switch self {
        case .running: return "arrow.triangle.2.circlepath"
        case .waitingForApproval: return "hand.raised.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    func color(providerColor: Color) -> Color {
        switch self {
        case .running: return providerColor
        case .waitingForApproval: return Theme.warn
        case .completed: return Theme.ok
        case .failed: return Theme.danger
        }
    }
}

private struct AgentHeaderUsageStrip: View {
    let usage: AgentUsage
    let windowsByProvider: [AgentProvider: [AgentUsageWindow]]

    var body: some View {
        HStack(spacing: 6) {
            if usage.totalTokens > 0 {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(Theme.warn)
                Text(usage.totalTokens.formattedCompact)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.72))
                Text("tokens".loc)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.36))
            }

            ForEach(providerEntries, id: \.provider.rawValue) { entry in
                HStack(spacing: 4) {
                    Text(entry.provider.displayName)
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.56))
                    ForEach(entry.windows) { window in
                        HStack(spacing: 2) {
                            Text(window.label)
                                .foregroundColor(.white.opacity(0.38))
                            Text("\(Int(window.remainingPercentage.rounded()))%")
                                .foregroundColor(windowColor(window))
                        }
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .help(windowHelp(entry.provider, window))
                    }
                }
                .padding(.horizontal, 5)
                .frame(height: 20)
                .background(Capsule().fill(Color.white.opacity(0.04)))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(Capsule().fill(Color.white.opacity(0.055)))
    }

    private var providerEntries: [(provider: AgentProvider, windows: [AgentUsageWindow])] {
        windowsByProvider
            .filter { !$0.value.isEmpty }
            .map { (provider: $0.key, windows: $0.value) }
            .sorted { $0.provider.rawValue < $1.provider.rawValue }
    }

    private func windowColor(_ window: AgentUsageWindow) -> Color {
        if window.usedPercentage >= 90 { return Theme.danger }
        if window.usedPercentage >= 70 { return Theme.warn }
        return Theme.ok
    }

    private func windowHelp(_ provider: AgentProvider, _ window: AgentUsageWindow) -> String {
        var value = "\(provider.displayName) · \(window.label) · \(Int(window.remainingPercentage.rounded()))% \("remaining".loc)"
        if let resetsAt = window.resetsAt {
            value += " · \("resets".loc) \(resetsAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return value
    }
}

private struct AgentUsageSurface: View {
    let usage: AgentUsage

    var body: some View {
        HStack(spacing: 18) {
            usageValue("Input".loc, value: usage.inputTokens)
            usageValue("Cached".loc, value: usage.cachedInputTokens)
            usageValue("Output".loc, value: usage.outputTokens)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent usage: %d input, %d cached, %d output tokens".locf(
            usage.inputTokens, usage.cachedInputTokens, usage.outputTokens
        ))
    }

    private func usageValue(_ title: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundColor(.white.opacity(0.36))
            Text(value.formattedCompact)
                .foregroundColor(.white.opacity(0.70))
        }
        .font(.system(size: 9.5, weight: .semibold, design: .rounded).monospacedDigit())
    }
}

private extension AgentSessionSnapshot {
    var projectName: String {
        guard let cwd, !cwd.isEmpty, cwd != "/" else { return provider.presentationTitle }
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? provider.presentationTitle : name
    }

    var previewText: String {
        if let preview = preview?.trimmingCharacters(in: .whitespacesAndNewlines),
           !preview.isEmpty {
            return preview
        }
        return phase.presentationTitle
    }

    var mascotStatus: AgentMascotStatus {
        if needsAttention { return .warning }
        if phase == .processing || phase == .starting { return .working }
        return .idle
    }

    var latestUserText: String? {
        conversationItems.last(where: { $0.kind == .user })?.text
    }

    var latestAssistantText: String? {
        conversationItems.last(where: {
            $0.kind == .assistant
        })?.text ?? preview
    }

    var relativeTime: String {
        let seconds = max(0, Int(Date().timeIntervalSince(lastActivityAt)))
        if seconds < 60 { return "\(max(seconds, 1))s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)d"
    }
}

private extension Date {
    var shortTime: String {
        AgentIslandDateFormatter.shared.string(from: self)
    }
}

private enum AgentIslandDateFormatter {
    static let shared: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension AgentProvider {
    var presentationTitle: String { displayName }

    var presentationColor: Color {
        switch self {
        case .claude: return Color(red: 0.98, green: 0.73, blue: 0.30)
        case .codex: return Color(red: 0.33, green: 0.67, blue: 1.00)
        case .gemini: return Color(red: 0.58, green: 0.47, blue: 0.96)
        case .qwen, .kimi, .qoder, .qoderCN, .qoderWork, .qoderCLI, .qoderCNCLI:
            return Color(red: 0.12, green: 0.88, blue: 0.56)
        case .codeBuddy, .codeBuddyCLI, .workBuddy:
            return Color(red: 0.80, green: 0.63, blue: 1.00)
        case .cursor, .trae, .jetBrains, .copilot:
            return Color(red: 0.40, green: 0.76, blue: 0.96)
        case .hermes, .openCode, .pi, .openClaw, .legacyImport:
            return Theme.textTertiary
        }
    }
}

private extension AgentPhase {
    var presentationTitle: String {
        switch self {
        case .starting: return "Starting".loc
        case .processing: return "Working".loc
        case .waitingForApproval: return "Waiting for approval".loc
        case .waitingForAnswer: return "Waiting for answer".loc
        case .completed: return "Completed".loc
        case .interrupted: return "Interrupted".loc
        case .failed: return "Failed".loc
        case .ended: return "Ended".loc
        case .archived: return "Archived".loc
        }
    }

    var presentationColor: Color {
        switch self {
        case .waitingForApproval, .waitingForAnswer: return Theme.warn
        case .completed: return Theme.ok
        case .failed: return Theme.danger
        case .starting, .processing: return Theme.info
        case .interrupted, .ended, .archived: return Theme.textTertiary
        }
    }
}

private extension Int {
    var formattedCompact: String {
        let value = Double(self)
        switch value {
        case 1_000_000...: return String(format: "%.1fM", value / 1_000_000)
        case 1_000...: return String(format: "%.1fK", value / 1_000)
        default: return "\(self)"
        }
    }
}
