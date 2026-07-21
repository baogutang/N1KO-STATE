# Research sources

Research reviewed on **2026-07-15** and refreshed for Ping Island v0.26.0 on **2026-07-21**. Recheck version-sensitive behavior when implementing a later work package.

## Apple design and accessibility

- [Settings — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/settings): settings discoverability and native macOS settings-window conventions.
- [Popovers — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/popovers/): transient scope, size, dismissal, smooth resizing, and detachable macOS popovers.
- [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/): native interaction and window expectations.
- [Motion — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/motion): purposeful motion and accessibility.
- [SwiftUI accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion): system Reduce Motion environment behavior.
- [Accessibility — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/accessibility): non-color channels, labels, and adaptable interfaces.
- [Keyboards — Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/keyboards): keyboard-first macOS interaction.
- [NSPopover](https://developer.apple.com/documentation/appkit/nspopover): AppKit popover lifecycle.
- [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview): native material-backed surfaces.

## Apple performance and energy

- [Optimize SwiftUI performance with Instruments — WWDC25](https://developer.apple.com/videos/play/wwdc2025/306/): update groups, long body/platform updates, Time Profiler, and hitches.
- [Understanding and improving SwiftUI performance](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance): unnecessary state-driven updates and cause/effect analysis.
- [Recording performance data](https://developer.apple.com/documentation/os/recording-performance-data): `OSSignposter` and Instruments correlation.
- [Energy Efficiency Guide for Mac Apps — Best Practices](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/BestPractices.html): idle, invisible content, main-thread work, batching, and timer tolerance.
- [Minimize Timer Usage](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html): timer wake cost and event-driven alternatives.
- [Extend App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html): proactive idle rather than passive App Nap reliance.
- [Avoid Extraneous Content Updates](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/UsingEfficientGraphics.html): avoid hidden/obscured updates and excessive animation.
- [ProcessInfo](https://developer.apple.com/documentation/foundation/processinfo): low-power and thermal-state signals.
- [WWDC22 proc_pid_rusage example](https://developer.apple.com/videos/play/wwdc2022/10106/?time=413): public libproc resource inspection.

## Apple fullscreen and screen APIs

- [NSWindow.CollectionBehavior.fullScreenAuxiliary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary): eligibility to coexist with a fullscreen primary window.
- [Fullscreen window programming guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/MOSXAppProgrammingGuide/FullScreenApp/FullScreenApp.html): native fullscreen Space behavior.
- [NSScreen.safeAreaInsets](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets): safe-area geometry used when identifying a physical camera housing.
- [NSScreen auxiliaryTopRightArea](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytoprightarea-gr2n): top auxiliary screen area.
- [NSWorkspace.activeSpaceDidChangeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification): a reconciliation signal without transition details.
- [NSEvent global monitor](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents%28matching%3Ahandler%3A%29): global pointer observation constraints.

## Open-source references inspected

- [Stats](https://github.com/exelban/stats) at inspected commit `8ab8e1ef405801f91b28050a660bf24cfb4587af`:
  - [Reader lifecycle](https://github.com/exelban/stats/blob/8ab8e1ef405801f91b28050a660bf24cfb4587af/Kit/module/reader.swift): popup/preview readers, start/pause/stop, per-reader cadence.
  - [Repeater](https://github.com/exelban/stats/blob/8ab8e1ef405801f91b28050a660bf24cfb4587af/Kit/plugins/Repeater.swift): background dispatch timer with leeway.
  - Useful for lifecycle/module boundaries; its process reader still uses `ps`, so that implementation is not copied.
- [Boring Notch](https://github.com/TheBoredTeam/boring.notch) at inspected commit `9b3403b559c813cf401212edb0615ce380d2834d`:
  - validates the value of per-display fullscreen state and zero-height behavior;
  - current fullscreen detection uses MacroVisionKit/private CGS information, which is not accepted for the N1KO shipping path.
- [MacroVisionKit FullScreenMonitor](https://github.com/TheBoredTeam/MacroVisionKit/blob/da481a6be8d8b1bf7fcb218507a72428bbcae7b0/Sources/MacroVisionKit/FullScreenMonitor.swift): useful reference for per-display Space identity; rejected as a production dependency because it calls private `CGSCopyManagedDisplaySpaces`.
- [Ice settings](https://github.com/jordanbaird/Ice/blob/main/Ice/Settings/SettingsView.swift): native macOS settings organization reference.
- [Maccy](https://github.com/p0deje/Maccy): keyboard-first macOS interaction reference.

## Agent capability source and licensing

- [Audited Agent source repository](https://github.com/erha19/ping-island): the source-level UI migration remains mapped to `da130d679e830894240e926184d29751dfd2def1` / v0.25.2; the latest audited capability snapshot is `c9148fc6a66a98f62dc1cac8fde415c2be9f2233` / v0.26.0. The v0.26.0 audit found no migrated Island UI-core, sound, LICENSE, or NOTICE change and selectively carried only the applicable provider/session delta.
- [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0): redistribution conditions for selected reused source.
- [Apache License FAQ](https://www.apache.org/foundation/license-faq.html): attribution and trademark boundaries.

The pinned snapshot is an input to the migration inventory, not a mandate to merge the repository or track its main branch automatically.
