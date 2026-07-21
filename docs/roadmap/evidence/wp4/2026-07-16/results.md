# WP4 Agent Island and fullscreen results — 2026-07-16

Checkout: `09cde29c24d20f8b97f0fd2995a686fac0cb3ab7` plus retained uncommitted
WP0–WP3 work and this WP4 implementation. No commit, push, tag, release, Developer ID signing,
notarization, or publication was performed.

## Delivered architecture

- `PresentationCoordinator` remains the sole presentation authority and owns one
  `AgentSurfaceCoordinator`. The latter receives the existing WP3 coordinator's immutable
  `AgentSnapshot`; no Agent store, hook owner, AppDelegate, updater, settings window, or response
  route was duplicated.
- `N1KOWindowCore` contains the two N1KO-owned AppKit window roles used by both the shipping app and
  the independent WindowServer harness. `DesktopIslandPanel` uses `.moveToActiveSpace`,
  `.stationary`, `.ignoresCycle`, and `.fullScreenNone`, with no `.fullScreenAuxiliary`.
  `FullscreenRevealPanel` is a separate, lazy, initially ordered-out auxiliary panel.
- Fullscreen detection is a public-API state machine driven by `NSWorkspace`/screen/lifecycle
  notifications and bounded 0/80/180/350/700/1200 ms generation-cancelled samples. Window coverage
  is compared only in Quartz coordinates after `NSScreenNumber -> CGDirectDisplayID -> UUID ->
  CGDisplayBounds` normalization. Optional AX fullscreen evidence is skipped without permission and
  runs off the main thread when available. No polling loop was added.
- Compact, expanded, intervention, completion, session-list, and usage views share the WP2 Calm
  Telemetry tokens, semantic text/icon channels, VoiceOver labels, keyboard actions, and central
  Reduce Motion policy. Snapshot projection is performed at most once per changed Agent generation.
- Agent Center is a destination in the one WP2 Settings router/window/search model. Its behavior,
  Island, fullscreen reveal, and UUID-backed target-screen settings are typed views over the one
  `AppSettings` authority. English, Simplified Chinese, and Traditional Chinese strings ship.
- Approve/deny/answer actions pass the snapshot's provider/session/request/owner/capability directly
  to WP3 `AgentSessionCoordinator.respond`; UI state does not retain a second mutable session truth.

## Native fullscreen structural evidence

Actual machine: macOS 15.7.7, Apple M4, one Kuycon G27P external display, 5120 by 2880 physical,
2560 by 1440 UI at 75 Hz, `safeAreaInsets.top == 0`.

The original roadmap candidate `.canJoinAllSpaces + .fullScreenNone` was not accepted on assumption.
The retained one-cycle calibration observed the desktop panel in all 3 post-enter WindowServer
samples. Replacing `.canJoinAllSpaces` with `.moveToActiveSpace` produced 0 of 3 samples in the next
calibration and then passed the full run:

| Native-fullscreen result | Value |
|---|---:|
| Real enter/exit cycles | 100 / 100 |
| Post-`didEnterFullScreen` WindowServer samples | 300 |
| Desktop-panel frames observed in fullscreen | **0** |
| Desktop restore failures after exit | **0** |
| Reveal panels constructed without dwell | **0** |
| Elapsed time | 161.292 s |

Direct artifacts: [100-cycle JSON](native-fullscreen-100-cycles.json),
[100-cycle log](native-fullscreen-100-cycles.txt),
[invalid can-join-all-spaces calibration](native-fullscreen-1-cycle-invalid-can-join-all-spaces.json),
and [passing one-cycle calibration](native-fullscreen-1-cycle-calibration.json).

Command:

```bash
N1KO_NATIVE_FULLSCREEN_CYCLES=100 \
N1KO_NATIVE_FULLSCREEN_OUTPUT=docs/roadmap/evidence/wp4/2026-07-16/native-fullscreen-100-cycles.json \
swift run --skip-build N1KOWP4FullscreenHarness
```

## Pseudo-fullscreen latency

The live AppKit harness expands a borderless layer-zero window to the actual target display, issues
the same reconciliation request used by public transition signals, and observes both WindowServer
visibility and the consecutive-evidence state machine.

- Desktop panel absent from WindowServer: **16.105 ms** after transition request.
- Stable `.fullscreen(.pseudo)` classification: **87.536 ms**.
- Both are below the documented 200 ms target.

The final record is [pseudo-fullscreen-live.txt](pseudo-fullscreen-live.txt). Two invalid attempts
are retained: the XCTest host was not the frontmost application in the first, and the second used a
titled window constrained below the menu bar and therefore reached only 92.99% coverage. The final
harness injects only its own PID while retaining the production Core Graphics path.

## Hidden rendering and resource result

Final-code optimized native scenario: 20-second warm-up, 35-second app measurement, 33 measured
seconds after the stack-sample allowance, Agent Core enabled with 200 restored sessions and zero
measured ingress.

| Average CPU | p95 | Wakeups/s | Start -> final footprint | Growth | Peak |
|---:|---:|---:|---:|---:|---:|
| **0.251%** | **0.800%** | **2.273** | 21.69 -> 23.34 MB | +1.66 MB | 24.13 MB |

At the measurement boundary and end: Agent surface visible=false, snapshot compositions=0, global
mouse monitors=0, retry tasks=0, ingress=0. The five-second stack sample contains no Agent surface,
AX, display-link, or repeating-animation stack. Source scans find no `CVDisplayLink`,
`CADisplayLink`, `repeatForever`, scheduled timer, or dispatch timer in the Agent surface path.

The first five-second-warm-up run is retained as invalid because Agent restoration/projection was
still draining (7.831% CPU, 77.7% p95). A later 0.402% diagnostic exposed a one-off 234 ms main-thread
AX wait; final code skips AX when permission is absent and moves evidence sampling to a serial
background queue. Final artifacts: [hidden scenario](agent-surface-hidden/),
[invalid short warm-up](agent-surface-hidden-invalid-short-warmup/), and
[pre-background-sampling diagnostic](agent-surface-hidden-pre-background-sampling/).

## Automated matrix and UI evidence

`WP4AgentSurfaceTests` covers:

- structural desktop/reveal collection-behavior separation;
- 100 deterministic native state cycles, reveal gating, exit stabilization, suspend/resume, and
  rapid-reconciliation generation cancellation;
- notched built-in, notchless external, built-in plus external, two external, left/right,
  above/below, mixed scale, menu-display reassignment, UUID selection, and disconnected-target
  fallback with synthetic AppKit/Quartz display descriptors;
- Safari/Chrome/video/IDE native, presentation, maximized, borderless pseudo, and helper-owned
  evidence classifications;
- pointer exit, Escape-equivalent dismissal, Space exit, screen/session suspension, lazy reveal,
  150–200 ms dwell bounds, and return of panels/monitors/retries to baseline;
- compact, expanded, intervention (including the empty-question answer fallback), completion,
  session-list, and usage rendering; N1KO motion/type bounds; all three Settings localizations at
  900 by 600;
- exact response routing and single-generation projection.

The final full suite executes **81 tests with zero failures and three expected skips**. The skips are
the unmounted installer DMG, the opt-in sustained process comparison, and the default-skipped live
pseudo-fullscreen test; the pseudo test was run separately above and passed. WP4 contributes 12
passing default tests plus that separately passing live gate.

The automated matrix exercises every display arrangement and application/lifecycle input listed in
`03-fullscreen-window-design.md`. Physical WindowServer coverage in this session was necessarily
limited to the attached single notchless external display. Mixed physical monitors, a notched
built-in panel, and toggling “Displays have separate Spaces” remain explicit WP6 hardware-soak
coverage; this is not represented as hardware that was present in WP4.

## Build, compatibility, identity, and safety verification

- `swift build`: pass; SwiftPM platform remains macOS 12.
- `swift test`: 81 tests, 0 failures, 3 expected skips.
- `plutil -lint Resources/Info.plist Localization/*/Localizable.strings`: pass.
- `bash -n` for build/performance/fullscreen/migration scripts: pass.
- `git diff --check`: pass.
- Shipping source scans for private `CGS*`/`SLS*`/SkyLight, upstream product branding, Agent-owned
  display links/timers/repeating animation, and Agent content fonts below 10 pt: clean.
- Source ownership scan reports exactly one AppDelegate, SettingsWindowController,
  PresentationCoordinator, and UpdateController. The product presentation targets instantiate no
  `AgentSessionStore`.
- Release native assembly, deep strict ad-hoc code-sign verification, and smoke: pass; final smoke
  idle CPU sample **0.0%**. `otool` reports `minos 12.0`. The bundle retains the exact 201-line
  Apache license and 15-line NOTICE under the legal-notice resource path.
- Monitor scheduling, history, alerts, fan control, helper ownership, and thermal safety code paths
  were not changed by WP4; the full regression suite, including fan safety tests, passes.

## Remaining risks handed forward

- Public APIs cannot expose exact menu-bar/fullscreen animation progress. Native fullscreen is
  structurally excluded; pseudo-fullscreen remains notification/evidence driven. A borderless
  same-application resize that emits neither app/Space/screen notification nor authorized AX change
  may not be detected until another public reconciliation signal.
- The 100-cycle physical result is for one notchless external display on macOS 15.7.7. Mixed
  physical display arrangements, a real notched panel, separate-Spaces disabled, and hardware
  sleep/wake remain WP6 physical-matrix risks despite passing synthetic coordinate/lifecycle tests.
- Global mouse movement monitoring is installed only in provisional/stable fullscreen while an
  Agent surface is eligible. macOS input-monitoring policy changes could affect global top-edge
  observation; local pointer and all dismissal paths remain available.
- WP5 still owns provider parity, focus/remote/tmux capabilities, managed hook takeover, coexistence,
  migration rollback, and legacy product-path cleanup. WP4 did not edit third-party hook config.
