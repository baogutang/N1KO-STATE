// N1KO modification notice: extracted from Ping Island commit da130d6
// SettingsWindowView.swift general/display sections and hosted by N1KO's sole
// Settings window. The native-fullscreen membership control remains N1KO-owned.

import SwiftUI

struct IslandSettingsContent: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            behaviorSection
            panelSection
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
    }

    private var behaviorSection: some View {
        SettingsSectionCard(title: "行为") {
            SettingsToggleLine(
                title: "无活跃会话时自动隐藏",
                subtitle: "当前没有正在运行或需要处理的会话时，自动隐藏 Island",
                isOn: $settings.autoHideWhenIdle
            )
            SettingsLineDivider()
            SettingsToggleLine(
                title: "智能抑制",
                subtitle: "当前正在看终端时，不自动弹出通知面板",
                isOn: binding(\.smartSuppression)
            )
            SettingsLineDivider()
            SettingsToggleLine(
                title: "完成时自动展开会话",
                subtitle: "消息完成后自动弹出结果面板；关闭后只保留刘海状态提示和提示音",
                isOn: binding(\.autoOpenCompletionPanel)
            )
            SettingsLineDivider()
            SettingsToggleLine(
                title: "上下文压缩时自动展开提醒",
                subtitle: "上下文压缩后自动弹出提示；关闭后只保留刘海状态提示和提示音",
                isOn: binding(\.autoOpenCompactedNotificationPanel)
            )
            SettingsLineDivider()
            SettingsToggleLine(
                title: "鼠标离开时自动收起",
                subtitle: "hover 展开的预览面板会在鼠标离开后自动关闭",
                isOn: binding(\.autoCollapseOnLeave)
            )
        }
    }

    private var panelSection: some View {
        SettingsSectionCard(title: "面板") {
            SettingsInfoLine(
                title: "展示模式",
                subtitle: settings.surfaceMode.subtitle
            ) {
                Picker("展示模式", selection: $settings.surfaceMode) {
                    ForEach(IslandSurfaceMode.allCases) { mode in
                        Text(appLocalized: mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .settingsMenuPicker(width: 180)
            }
            SettingsLineDivider()

            if settings.surfaceMode == .notch {
                SettingsInfoLine(
                    title: "显示密度",
                    subtitle: settings.notchDisplayMode.subtitle
                ) {
                    Picker("显示密度", selection: $settings.notchDisplayMode) {
                        ForEach(NotchDisplayMode.allCases) { mode in
                            Text(appLocalized: mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .settingsMenuPicker(width: 180)
                }
                SettingsLineDivider()
                SettingsSliderLine(
                    title: "静默状态宽度",
                    subtitle: "调整无展开面板时的刘海宽度；较窄时会降级为单图标显示，不影响点击或 hover 后的展开面板宽度。",
                    value: $settings.notchModuleWidth,
                    range: AppSettings.notchModuleWidthRange,
                    step: 4,
                    format: { "\(Int($0.rounded())) pt" }
                )
                SettingsLineDivider()
                SettingsInfoLine(
                    title: "右侧展示内容",
                    subtitle: "默认显示会话数量；检测到 Claude Code 或 Codex 的 7d 用量后，可改为展示其中一个客户端的 Token 剩余额度。"
                ) {
                    Picker("右侧展示内容", selection: binding(\.closedNotchTrailingContentMode)) {
                        ForEach(ClosedNotchTrailingContentMode.allCases) { mode in
                            Text(appLocalized: mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .settingsMenuPicker(width: 180)
                }
                SettingsLineDivider()
                SettingsInfoLine(
                    title: "刘海拖拽引导",
                    subtitle: "重新演示老用户首次打开新版本时看到的刘海拖拽提示。"
                ) {
                    Button("重新演示") { replayDetachmentHint() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            } else {
                SettingsInfoLine(
                    title: "宠物大小",
                    subtitle: settings.floatingPetSizeMode.subtitle
                ) {
                    Picker("宠物大小", selection: $settings.floatingPetSizeMode) {
                        ForEach(FloatingPetSizeMode.allCases) { mode in
                            Text(appLocalized: mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .settingsMenuPicker(width: 180)
                }
            }

            SettingsLineDivider()
            SettingsToggleLine(
                title: "显示代理活动详情",
                subtitle: "在会话列表和 hover 预览里展示工具调用、思考与更细的状态描述",
                isOn: binding(\.showAgentDetail)
            )
            SettingsLineDivider()
            SettingsToggleLine(
                title: "显示用量",
                subtitle: "在展开面板顶部显示 Claude 与 Codex 的限额占用率和重置时间",
                isOn: binding(\.showUsage)
            )
            SettingsLineDivider()
            SettingsInfoLine(
                title: "用量显示方式",
                subtitle: "切换显示已用量或剩余量；Claude 与 Codex 共用这组设置"
            ) {
                Picker("用量显示方式", selection: binding(\.usageValueMode)) {
                    ForEach(UsageValueMode.allCases) { mode in
                        Text(appLocalized: mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .settingsMenuPicker(width: 180)
                .disabled(!settings.showUsage)
            }
            SettingsLineDivider()
            SettingsSliderLine(
                title: "内容字号",
                subtitle: "调整会话列表、hover 预览和结果视图的文字大小",
                value: binding(\.contentFontSize),
                range: 11...17,
                step: 1,
                format: { "\(Int($0.rounded())) pt" }
            )
            SettingsLineDivider()
            SettingsSliderLine(
                title: "最大面板高度",
                subtitle: "控制聊天面板和 hover 预览的最大展开高度",
                value: $settings.maxPanelHeight,
                range: 480...700,
                step: 10,
                format: { "\(Int($0.rounded())) pt" }
            )
        }
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0 }
        )
    }

    private func replayDetachmentHint() {
        settings.notchDetachmentHintPending = true
        settings.floatingPetSettingsHintPending = true
        NotificationCenter.default.post(name: .n1koPresentNotchDetachmentHint, object: nil)
    }
}
