# WP4 pinned Ping-Island source parity evidence

Date: 2026-07-17

Acceptance source: local checkout
`<local-ping-island-checkout>` at
`da130d679e830894240e926184d29751dfd2def1` (v0.25.2).

## Outcome

The shipping Agent Island no longer hosts the earlier N1KO-authored approximation. The desktop and
fullscreen-reveal panels host the pinned `NotchViewController` and `NotchView`; the floating surface
hosts the pinned `DetachedIslandWindowController` and `DetachedIslandPanelView`. The exact pinned UI
state machine, route resolver, list/detail/question/completion hierarchy, provider Canvas mascots,
detachment gesture, measured sizing, event monitors, and energy governor now execute in the N1KO app.

N1KO retains the required ownership boundaries: one app lifecycle, one `AppSettings`, one updater,
one `PresentationCoordinator`, and one `AgentSessionCoordinator`. Boundary adapters project N1KO
snapshots/settings/actions into the pinned UI types and start no second sockets, watchers, store,
runtime, updater, analytics client, or settings repository.

## File-level source comparison

The `Sources/N1KOState/Views/PingParity` migration contains 72 Swift files:

- 41 files are byte-identical to the same relative path at the pinned commit;
- 24 files retain the pinned source structure but are adapted for macOS 12, N1KO identity,
  single-owner routing, or the fullscreen boundary;
- 7 N1KO boundary files have no same-path upstream file: the two runtime/session adapters,
  settings/sound compatibility types, the hook-event projection, and the source-extracted
  behavior/display and sound settings content hosted by N1KO's sole settings window.

All 24 modified same-path files begin with a prominent N1KO modification notice. The modified set is:

```text
Core/EnergyGovernor.swift
Core/FeatureFlags.swift
Core/NotchActivityCoordinator.swift
Core/NotchViewModel.swift
Core/SoundPackCatalog.swift
Models/ClientProfile.swift
Services/Session/ConversationParser.swift
Services/Usage/AgentUsageAnalytics.swift
Services/Usage/UsageSummaryPresenter.swift
UI/Components/PixelNumberView.swift
UI/Components/SessionQuestionForm.swift
UI/Views/ChatView.swift
UI/Views/CodexSessionView.swift
UI/Views/DetachedIslandPanelView.swift
UI/Views/MascotSettingsView.swift
UI/Views/NotchHeaderView.swift
UI/Views/NotchView.swift
UI/Views/SessionCompletionNotificationView.swift
UI/Views/SessionHoverPreviewView.swift
UI/Views/SessionListView.swift
UI/Views/UsageSummaryStripView.swift
UI/Window/DetachedIslandWindowController.swift
Utilities/SessionTextSanitizer.swift
Utilities/TerminalVisibilityDetector.swift
```

The count is produced by comparing every local relative path with the pinned checkout using `cmp`;
it is not a filename-only or visual estimate.

## Runtime ownership and action routing

- `AgentSurfaceCoordinator.prepareDesktopPanel()` and `prepareRevealPanel()` instantiate the pinned
  `NotchViewController`.
- `AgentSurfaceCoordinator.prepareDetachedController()` instantiates the pinned
  `DetachedIslandWindowController`.
- `SessionMonitor` is an adapter over immutable N1KO `AgentSnapshot` values. Approve, deny, answers,
  archive, follow-up, usage, conversation, completion, and provider identity route back to the sole
  N1KO owner.
- Pinned list/detail activation actions resolve their source snapshot through
  `N1KOSessionActionRouter` and call the N1KO integration controller's public tmux/terminal/IDE focus
  route. They do not create a second launcher owner.
- Source-native Claude/Codex launch and process termination remain disabled because N1KO observes
  externally owned sessions and has no safe native-runtime owner for those actions.
- Non-tmux Codex follow-up remains unavailable because app-server ingress has no concrete
  authenticated outbound sender. Unsupported actions remain absent rather than simulated.

## Settings, sound, and mascot parity

- Pinned `NotchView.openSettingsWindow()` still calls the source-compatible
  `SettingsWindowController.shared.present()`, but N1KO's `PresentationCoordinator` now injects the
  sole window's monitor/fan dependencies during startup. A focused fresh-controller test proves the
  first click selects Agent Center and creates one settings window without requiring a prior menu
  entry.
- Agent Center now also hosts source-extracted Island behavior/display controls: automatic hiding,
  smart suppression, separate completion and context-compaction auto-open, mouse-leave collapse,
  notch versus floating-pet presentation, compact/detailed density, silent width, trailing content,
  pet size, activity details, usage mode, content font, and maximum panel height. Presentation-mode
  changes are observed by the existing `AgentSurfaceCoordinator` and switch its N1KO-owned surface;
  they do not create an upstream window owner. Native-fullscreen membership remains governed only by
  N1KO's public-API dual-window state machine and is intentionally not exposed as an upstream toggle.
- The previous N1KO-authored two-event sound approximation and duplicate playback owner were
  removed. Agent Center now hosts source-extracted `SoundSettingsContent`, adapted
  `SoundPackCatalog`, and source `MascotSettingsView` behind the sole `AppSettings` authority.
- Sound parity covers the source's master toggle, volume, five independent event enable/mapping
  controls, system sound mode, fixed 8-bit mode with client startup sound, and OpenPeon/CESP pack
  mode with automatic discovery, manual directory import, event-category mapping, preview, and
  no-immediate-repeat selection.
- The pinned fixed startup cue is invoked from N1KO's own `AppDelegate` after normal launch; only the
  opt-in performance-benchmark launch suppresses it so measurement semantics remain deterministic.
  Legacy N1KO sound choices migrate only when actually persisted, while untouched installs receive
  the pinned event defaults.
- N1KO adds only boundary security to imported packs: a 256 KiB manifest cap, non-empty pack names,
  extension and magic-byte checks, traversal rejection, and symlink-resolved containment. These
  checks do not create another sound/settings owner.
- Mascot settings retain all 13 clients, per-client defaults/overrides, live idle/working/warning
  preview, reset actions, and status help.

## Fullscreen exception requested by the user

This is the intentional behavioral exception to the pinned project:

- desktop panel: `.moveToActiveSpace + .stationary + .ignoresCycle + .fullScreenNone`;
- detached panel: `.moveToActiveSpace + .stationary + .ignoresCycle + .fullScreenNone`;
- neither ordinary surface has `.fullScreenAuxiliary` or `.canJoinAllSpaces`;
- only the normally hidden reveal panel has `.fullScreenAuxiliary`, and it is shown after stable
  fullscreen classification plus deliberate 180 ms top-edge dwell.

The retained physical 100-cycle evidence remains 0/300 desktop-panel samples visible in native
fullscreen, zero restore failures, and zero reveal construction without dwell. The UI source port did
not change this state machine or collection-behavior boundary.

## Visual evidence generated from the pinned source view

The first four 2x captures render the migrated `NotchView` directly with a fixed 1512 x 982 display
geometry and immutable N1KO session fixtures. The gray field is capture-only contrast; the black
Island and its contents are the shipping pinned-source view. The final six captures render the
source-extracted Island behavior/display, sound, and mascot settings hosted by N1KO at deterministic
740-point widths in dark appearance.

- [compact](ping-island-source-parity/ping-source-compact.png)
- [click-expanded session list](ping-island-source-parity/ping-source-click.png)
- [hover dashboard](ping-island-source-parity/ping-source-hover.png)
- [fullscreen reveal content](ping-island-source-parity/ping-source-fullscreen-reveal.png)
- [notch presentation and display settings](ping-island-source-settings/ping-source-island-settings-notch.png)
- [floating-pet presentation and display settings](ping-island-source-settings/ping-source-island-settings-floatingPet.png)
- [system-sound settings](ping-island-source-settings/ping-source-sound-settings-builtIn.png)
- [fixed 8-bit settings](ping-island-source-settings/ping-source-sound-settings-island8Bit.png)
- [OpenPeon/CESP settings](ping-island-source-settings/ping-source-sound-settings-soundPack.png)
- [client mascot settings](ping-island-source-settings/ping-source-mascot-settings.png)

The test `testRuntimeHostsPinnedNotchAndDetachedControllers` separately proves that production
controller factories use the pinned controllers, so these captures are no longer evidence from the
retired custom shell. Direct user visual/interaction acceptance remains open.

## Legal and identity evidence

- `ThirdPartyLicenses/Ping-Island-Apache-2.0.txt` is byte-identical to pinned `LICENSE.md`:
  SHA-256 `d8b6cb6571c65d3dfaa4983b2ba20d19887ab5d1269e963eb3817ceb0c0e1447`.
- `ThirdPartyLicenses/Ping-Island-NOTICE.txt` is byte-identical to pinned `NOTICE`:
  SHA-256 `ad648dd4a96456b339021d2c730ed535759432e9468c04d310ba602ef2c7b42a`.
- The native app bundle contains both files plus the project notice, Sparkle license, and SMCKit
  license.
- Executable identifiers, environment keys, settings keys, support paths, hook names, notifications,
  and profile paths use N1KO identity. Remaining upstream strings are confined to source/legal
  attribution and exact legacy-import/takeover constants.
- Following explicit user approval, the 13 files in pinned `PingIsland/Resources/Sounds` are bundled
  byte-identically under `Resources/Sounds`; their exact SHA-256 inventory is recorded below and the
  same inventory is checked from `Resources/Sounds/SHA256SUMS` against source and built app by the
  release gate. The existing Apache LICENSE/NOTICE applies. Upstream fonts, product icons, screenshots, telemetry,
  updater, AppDelegate, settings owner, and other assets with unproven provenance are not bundled.

```text
fde00186690edd954b745b54ed4da2176e18dae0ff6e5651af1e77fdec75bcdb  8bit_approval_alert.wav
a111730b7a4f8f9c181450d8f68cd43f4f41124291ae6568571a8d836cbe0972  8bit_boot_jingle.wav
ab9fcc1972971f6619a237faf4bcd492ab2010306de82bcb8f86f51858c7488f  8bit_complete_ding.wav
bf521d2824625c4b6478cf8a062781ea555424fdcbc1e5375a16ea327fa90bf7  8bit_error_buzz.wav
5595b4afaa882b7d6f6ef47be1d3f3e08066f243c01bb43077c396418f9df0ba  8bit_hurt.wav
bc933c511fa749082c36b572747ff0a4be14852e12ef1194991fb484b927e512  8bit_item_pickup.wav
50ce93565c997fdaa29f49ea2fd62e876440141d70d2da5f116c3633b247dc00  8bit_menu_highlight.wav
61d843ae8de7f89e5ce300d6b36587b7768cdc08ce3ff60854d21eac25e4d001  8bit_menu_select.wav
3a1d1a187dd94eefcb8d154e04a2b22c1554dbb9556c26df8debe597a5fb6325  8bit_power_up.wav
3040eeaf607d888616e7c5d2e1c5a9e0d626d6134d30d23be82da723da1ad2f1  8bit_start_chime.wav
1dff7af4871b4c79738f49e005e38e04f84d8a7aae3481320ebdc510b0cab99a  8bit_submit_blip.wav
9545dd734a9c41170bb48761b752b762445d3e450717fba3b93c3c256ca4bb9d  8bit_win_jingle.wav
e889aec9c5dc5a8db7a5df260204680c7883673de7e61d04776dee6bdc865af7  bubbles_pop.wav
```

## Verification

- `swift build`: passed.
- `swift test`: 129 executed, 3 expected environment/opt-in skips, 0 failures.
- `WP4AgentSurfaceTests`: 28 executed, 1 opt-in live WindowServer skip, 0 failures.
- Pinned runtime-host, N1KO-to-Ping state/mascot, source-view render, route, completion, question,
  detached placement, 100-cycle synthetic state-machine, and single-owner response tests passed.
- `plutil -lint Resources/Info.plist Localization/*/Localizable.strings`: passed.
- Localization uniqueness, `git diff --check`, shell syntax, N1KO identity, one-owner, minos 12.0,
  ad-hoc signature, source/undefined-symbol private API, and legal-bundle gates passed.
- `./build_app.sh --native --smoke`: Release arm64 assembly and short launch smoke passed. An
  incidental launch-time process snapshot is not treated as performance evidence; no Menu Bar
  occupancy matrix or long soak was run.
- No commit, push, tag, release, notarization, upload, or update publication was performed.

## Status and remaining risk

WP4 remains **In Progress / sole Next** until the user accepts the live visual and interaction result
or asks to expand the product boundary. The remaining source-runtime differences are the disabled
native launch/terminate actions, missing authenticated non-tmux Codex sender, conservative exact-PID
focus-suppression detection, excluded unproven upstream product assets, macOS 12 API backports,
the required fullscreen exception above, and existing Swift 6 actor-isolation warning debt in the
notification/fullscreen coordinator paths. The current Swift 5.9/macOS 12 build passes, but that
warning debt must be resolved before a Swift 6 language-mode migration. WP6 remains paused.
