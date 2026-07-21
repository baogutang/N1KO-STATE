// N1KO modification notice: extracted from Ping Island commit da130d6
// SettingsWindowView.swift and hosted by N1KO's sole Settings window.

import AppKit
import SwiftUI

struct SoundSettingsContent: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var soundPacks = SoundPackCatalog.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsSectionCard(title: "通知") {
                SettingsToggleLine(
                    title: "启用提示音",
                    subtitle: "不同阶段可分别播放不同音效，适用于 Claude、Codex 等会话。",
                    isOn: $settings.soundEnabled
                )
                SettingsLineDivider()

                SettingsInfoLine(
                    title: "声音模式",
                    subtitle: "系统音适合快速配置；主题包兼容 OpenPeon / CESP 格式。"
                ) {
                    soundThemeModePicker
                }
                SettingsLineDivider()

                SettingsSliderLine(
                    title: "音量",
                    subtitle: "控制 Island 播放提示音时的音量大小",
                    value: $settings.soundVolume,
                    range: 0...1,
                    step: 0.05,
                    format: { "\(Int(($0 * 100).rounded()))%" },
                    showsTickMarks: true
                )
            }

            if settings.soundThemeMode == .builtIn {
                SoundEventSection(title: "阶段音效") {
                    ForEach(Array(NotificationEvent.allCases.enumerated()), id: \.element.id) { index, event in
                        SoundEventSettingsLine(
                            event: event,
                            isEnabled: soundEnabledBinding(for: event),
                            selectedSound: soundBinding(for: event)
                        ) {
                            AppSettings.playSound(for: event)
                        }

                        if index < NotificationEvent.allCases.count - 1 {
                            SettingsLineDivider()
                        }
                    }
                }
            } else if settings.soundThemeMode == .island8Bit {
                SettingsSectionCard(title: "客户端启动音") {
                    SoundStartupLine {
                        AppSettings.playClientStartupSound()
                    }
                }

                SoundEventSection(title: "阶段音效") {
                    ForEach(Array(NotificationEvent.allCases.enumerated()), id: \.element.id) { index, event in
                        BundledSoundEventLine(
                            event: event,
                            isEnabled: soundEnabledBinding(for: event),
                            selectedSound: bundledSoundBinding(for: event)
                        ) {
                            AppSettings.playSound(for: event)
                        }

                        if index < NotificationEvent.allCases.count - 1 {
                            SettingsLineDivider()
                        }
                    }
                }
            } else {
                SettingsSectionCard(title: "主题音效包") {
                    SoundPackSourceInfoLine {
                        soundPackPicker
                    }

                    SoundPackImportActionLine {
                        if soundPacks.importPack(), soundPacks.pack(for: settings.selectedSoundPackPath) == nil {
                            settings.selectedSoundPackPath = soundPacks.availablePacks.first?.rootURL.path ?? ""
                        }
                    } accessory: {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.72))
                    }

                    if soundPacks.availablePacks.isEmpty {
                        SettingsValueLine(title: "可用主题包", value: AppLocalization.string("未发现"))
                    } else {
                        SettingsValueLine(title: "可用主题包", value: "\(soundPacks.availablePacks.count)")
                    }
                }

                SoundEventSection(title: "阶段映射") {
                    ForEach(Array(NotificationEvent.allCases.enumerated()), id: \.element.id) { index, event in
                        SoundPackEventLine(
                            event: event,
                            isEnabled: Binding(
                                get: { AppSettings.isSoundEnabled(for: event) },
                                set: { AppSettings.setSoundEnabled($0, for: event) }
                            )
                        ) {
                            AppSettings.playSound(for: event)
                        }

                        if index < NotificationEvent.allCases.count - 1 {
                            SettingsLineDivider()
                        }
                    }
                }
            }
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .onAppear {
            soundPacks.refresh()
            ensureValidSelectedSoundPack()
        }
        .onChange(of: soundPacks.availablePacks) { _ in
            ensureValidSelectedSoundPack()
        }
        .onChange(of: settings.soundThemeMode) { _ in
            ensureValidSelectedSoundPack()
        }
    }

    private var soundThemeModePicker: some View {
        Picker("声音模式", selection: $settings.soundThemeMode) {
            ForEach(SoundThemeMode.allCases) { mode in
                Text(appLocalized: mode.title).tag(mode)
            }
        }
        .labelsHidden()
        .settingsMenuPicker(width: 168)
    }

    private var soundPackPicker: some View {
        Picker("主题包", selection: $settings.selectedSoundPackPath) {
            if soundPacks.availablePacks.isEmpty {
                Text(appLocalized: "未发现").tag("")
            } else {
                ForEach(soundPacks.availablePacks) { pack in
                    Text(pack.displayName).tag(pack.rootURL.path)
                }
            }
        }
        .labelsHidden()
        .settingsMenuPicker(width: 204)
    }

    private func soundEnabledBinding(for event: NotificationEvent) -> Binding<Bool> {
        switch event {
        case .processingStarted: return $settings.processingStartSoundEnabled
        case .attentionRequired: return $settings.attentionRequiredSoundEnabled
        case .taskCompleted: return $settings.taskCompletedSoundEnabled
        case .taskError: return $settings.taskErrorSoundEnabled
        case .resourceLimit: return $settings.resourceLimitSoundEnabled
        }
    }

    private func soundBinding(for event: NotificationEvent) -> Binding<NotificationSound> {
        switch event {
        case .processingStarted: return $settings.processingStartSound
        case .attentionRequired: return $settings.attentionRequiredSound
        case .taskCompleted: return $settings.taskCompletedSound
        case .taskError: return $settings.taskErrorSound
        case .resourceLimit: return $settings.resourceLimitSound
        }
    }

    private func bundledSoundBinding(for event: NotificationEvent) -> Binding<Island8BitSound> {
        switch event {
        case .processingStarted: return $settings.island8BitProcessingStartSound
        case .attentionRequired: return $settings.island8BitAttentionRequiredSound
        case .taskCompleted: return $settings.island8BitTaskCompletedSound
        case .taskError: return $settings.island8BitTaskErrorSound
        case .resourceLimit: return $settings.island8BitResourceLimitSound
        }
    }

    private func ensureValidSelectedSoundPack() {
        guard settings.soundThemeMode == .soundPack else { return }
        if soundPacks.availablePacks.isEmpty {
            settings.selectedSoundPackPath = ""
        } else if soundPacks.pack(for: settings.selectedSoundPackPath) == nil {
            settings.selectedSoundPackPath = soundPacks.availablePacks.first?.rootURL.path ?? ""
        }
    }
}

private struct SettingsGlassSurface: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // Ping Island's settings surface is authored as a dark glass panel.
        // N1KO also supports a light app theme, so keep the source panel's
        // material dark instead of allowing white text to land on Aqua glass.
        view.appearance = NSAppearance(named: .darkAqua)
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.appearance = NSAppearance(named: .darkAqua)
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct SettingsSectionCard<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(appLocalized: title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 10)

            VStack(spacing: 0) { content }
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.045))
                        .overlay(
                            SettingsGlassSurface(material: .hudWindow, blendingMode: .withinWindow)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .opacity(0.96)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.08),
                                            Color.white.opacity(0.025),
                                            Color.black.opacity(0.04)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.11), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.16), radius: 18, y: 10)
        }
    }
}

struct SettingsLineDivider: View {
    var body: some View {
        Divider().overlay(Color.white.opacity(0.10)).padding(.horizontal, 18)
    }
}

struct SettingsToggleLine: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 16) {
                Text(appLocalized: title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer(minLength: 12)
                Toggle("", isOn: $isOn).labelsHidden().settingsCompactSwitch()
            }
            if let subtitle {
                Text(appLocalized: subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func settingsCompactSwitch(scale: CGFloat = 0.84) -> some View {
        toggleStyle(.switch)
            .controlSize(.small)
            .scaleEffect(scale)
            .frame(width: 32, height: 18)
    }

    func settingsMenuPicker(width: CGFloat) -> some View {
        pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: width, alignment: .trailing)
    }
}

struct SettingsInfoLine<Accessory: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 16) {
                Text(appLocalized: title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer(minLength: 12)
                accessory
            }
            if let subtitle {
                Text(appLocalized: subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SoundPackSourceInfoLine<Accessory: View>: View {
    @ViewBuilder let accessory: Accessory
    private let sourcePaths = ["~/.openpeon/packs", ".claude/hooks/peon-ping/packs"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                Text(appLocalized: "当前主题包")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer(minLength: 12)
                accessory
            }
            Text(appLocalized: "自动扫描以下目录，也支持手动导入本地目录。")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(sourcePaths, id: \.self) { path in
                    SettingsCodeCapsule(text: path, systemImage: "folder")
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SoundPackImportActionLine<Accessory: View>: View {
    let action: () -> Void
    @ViewBuilder let accessory: Accessory

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 16) {
                    Text(appLocalized: "导入本地主题包")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer(minLength: 12)
                    accessory
                }
                Text(appLocalized: "选择一个本地目录，导入后会加入可选列表。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(appLocalized: "目录内需要包含以下清单文件")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.42))
                    SettingsCodeCapsule(text: "openpeon.json", systemImage: "doc.text")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsCodeCapsule: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.42))
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.74))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

private struct SettingsValueLine: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 16) {
            Text(appLocalized: title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            Spacer(minLength: 12)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.72))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsSliderLine: View {
    let title: String
    let subtitle: String?
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String
    var showsTickMarks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(appLocalized: title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer(minLength: 12)
                Text(format(value))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.72))
            }
            if let subtitle {
                Text(appLocalized: subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Slider(value: $value, in: range, step: step).tint(TerminalColors.blue)
            if showsTickMarks {
                HStack(spacing: 0) {
                    ForEach(0..<17, id: \.self) { _ in
                        Capsule().fill(Color.white.opacity(0.28)).frame(width: 1, height: 6)
                        Spacer(minLength: 0)
                    }
                    Capsule().fill(Color.white.opacity(0.28)).frame(width: 1, height: 6)
                }
                .padding(.horizontal, 6)
                .padding(.top, -7)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct SoundEventSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        SettingsSectionCard(title: title) { VStack(spacing: 0) { content } }
    }
}

private struct SoundStartupLine: View {
    let preview: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.96, green: 0.63, blue: 0.22),
                                Color(red: 0.62, green: 0.35, blue: 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white.opacity(0.92))
            }
            .frame(width: 52, height: 52)
            .shadow(color: Color(red: 0.96, green: 0.48, blue: 0.12).opacity(0.24), radius: 14, y: 7)
            SoundEventTextBlock(
                title: "固定启动音",
                subtitle: "使用内置 8-bit 启动旋律。应用启动时会自动播放，也可以在这里试听。"
            )
            Spacer(minLength: 14)
            SoundPreviewButton(isEnabled: true, action: preview)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SoundEventTextBlock: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(appLocalized: title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(0.88)
            Text(appLocalized: subtitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }
}

private struct SoundPreviewButton: View {
    let isEnabled: Bool
    var size: CGFloat = 28
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.30, weight: .bold))
                .foregroundColor(.white.opacity(isEnabled ? 0.86 : 0.32))
                .offset(x: 1)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isEnabled ? 0.075 : 0.025))
                        .overlay(Circle().strokeBorder(Color.white.opacity(isEnabled ? 0.13 : 0.05), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .help("试听")
    }
}

private struct SoundControlCluster<PickerContent: View>: View {
    @Binding var isEnabled: Bool
    let pickerWidth: CGFloat
    let preview: () -> Void
    @ViewBuilder let picker: PickerContent

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            picker
                .settingsMenuPicker(width: pickerWidth)
                .disabled(!isEnabled)
                .frame(width: pickerWidth, alignment: .trailing)
            SoundPreviewButton(isEnabled: isEnabled, action: preview)
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .settingsCompactSwitch(scale: 0.88)
                .frame(width: 36, alignment: .center)
        }
        .frame(width: pickerWidth + 80, alignment: .trailing)
    }
}

private struct SoundEventSettingsLine: View {
    let event: NotificationEvent
    @Binding var isEnabled: Bool
    @Binding var selectedSound: NotificationSound
    let preview: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            SoundEventTextBlock(title: event.title, subtitle: event.subtitle)
            Spacer(minLength: 24)
            SoundControlCluster(isEnabled: $isEnabled, pickerWidth: 190, preview: preview) {
                Picker(event.title, selection: $selectedSound) {
                    ForEach(NotificationSound.allCases, id: \.self) { sound in
                        Text(sound.rawValue).tag(sound)
                    }
                }
                .id(selectedSound)
                .labelsHidden()
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }
}

private struct SoundPackEventLine: View {
    let event: NotificationEvent
    @Binding var isEnabled: Bool
    let preview: () -> Void

    private var categorySummary: String { event.cespCategories.joined(separator: ", ") }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                SoundEventTextBlock(title: event.title, subtitle: event.subtitle)
                Text(categorySummary)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.38))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)
            Spacer(minLength: 24)
            HStack(spacing: 8) {
                SoundPreviewButton(isEnabled: isEnabled, action: preview)
                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .settingsCompactSwitch(scale: 0.88)
                    .frame(width: 36, alignment: .center)
            }
            .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }
}

private struct BundledSoundEventLine: View {
    let event: NotificationEvent
    @Binding var isEnabled: Bool
    @Binding var selectedSound: Island8BitSound
    let preview: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            SoundEventTextBlock(title: event.title, subtitle: event.subtitle)
            Spacer(minLength: 24)
            SoundControlCluster(isEnabled: $isEnabled, pickerWidth: 190, preview: preview) {
                Picker(event.title, selection: $selectedSound) {
                    ForEach(Island8BitSound.allOrdered) { sound in
                        Text(sound.label).tag(sound)
                    }
                }
                .id(selectedSound)
                .labelsHidden()
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 18)
    }
}
