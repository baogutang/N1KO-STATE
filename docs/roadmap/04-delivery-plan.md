# 04 — Delivery plan and acceptance gates

The packages below are dependency ordered. Do not merge them into one large implementation. Each package must leave the app buildable and must update [README.md](README.md) with direct evidence before the next package starts.

## WP0 — Baseline and boundary freeze

Status: **Complete — remaining optional matrices explicitly deferred by user on 2026-07-16**

### Deliverables

1. Add signpost intervals/events for:
   - scheduling plan;
   - each sampler;
   - snapshot commit;
   - menu-bar render;
   - Quick Panel render/update;
   - settings preview render;
   - process scan;
   - Agent ingress/session publication once the target exists.
2. Define reproducible settings fixtures and measurement scenarios:
   - menu-bar-only background;
   - cards and gauges with all modules;
   - each settings destination visible;
   - settings used then closed;
   - 100 panel/settings cycles;
   - lock/screen sleep/system sleep/wake;
   - manual fan, curve, and thermal alert paths.
3. Record optimized-build Time Profiler, SwiftUI, Animation Hitches, wakeup, and footprint baselines: two-minute warm-up, ten-minute trace, three repetitions.
4. Add sampler/publication counters usable in tests and diagnostics.
5. Compile a representative Agent model/store/parser slice against macOS 12 and the current toolchain; list every incompatible API and estimate backport impact.
6. Pin the upstream commit and create a file-level migration inventory with one of: reuse, adapt behind protocol, rewrite, exclude until parity package.
7. Produce the Apache/OFL/asset/license inventory and identify which assets are not safe to migrate without further proof.
8. Record decisions for minimum macOS and first Agent release slice.

### Gates

- Every benchmark is repeatable from documented commands and fixtures.
- The current resource claim is either proven or marked for correction.
- The deployment decision is explicit; no silent minimum-version change.
- Every upstream file considered for reuse has an ownership/license disposition.
- Roadmap status and evidence are updated.

### Evidence

Collected on 2026-07-15 from checkout `09cde29c24d20f8b97f0fd2995a686fac0cb3ab7`
plus the uncommitted WP0 implementation. WP0 is **not Complete** because the direct Instruments and
manual lifecycle/safety gates listed below remain open.

#### Implementation and reproducibility

- Long-lived `os_signpost` intervals/events and lock-protected counters now cover scheduling,
  every current sampler, process scan, snapshot commit, menu-bar render, Quick Panel root update,
  and settings preview render. The counters are also included in diagnostic export.
- Reproducible fixture: `Fixtures/Performance/baseline-all-modules-2s.plist`.
- Runner: `scripts/run_performance_baseline.sh`; native rusage helper:
  `scripts/performance/proc_metrics.c`. The helper converts Mach absolute CPU time through
  `mach_timebase_info`; a two-second saturated-process calibration measured 2.001 seconds.
- Benchmark-only lifecycle automation validates expected surface state, ignores user status-item
  clicks, keeps Quick Panel visible without changing production transient behavior, backs up and
  restores defaults only after the benchmark process has fully exited, and proves exactly 100
  completed lifecycle cycles.
- Protocol, raw artifacts, invalid-run audit trail, and result interpretation:
  [WP0 baseline protocol](wp0-performance-baseline.md) and
  [2026-07-15 results](evidence/wp0/2026-07-15/results.md).

Formal command shape:

```bash
SKIP_BUILD=1 WARMUP_SECONDS=120 MEASUREMENT_SECONDS=600 REPETITIONS=3 \
  OUTPUT_ROOT=docs/roadmap/evidence/wp0/2026-07-15/<scenario> \
  scripts/run_performance_baseline.sh <scenario>
```

#### Formal baseline results

| Scenario | Average CPU median (range) | p95 median (range) | Wakeups/s median | Footprint median | Gate |
|---|---:|---:|---:|---:|---|
| Menu-bar-only | 0.218% (0.190–0.310) | 0.600% (0.400–0.800) | 1.960 | 19.67 MB | Pass |
| Quick Panel cards/all modules | 5.933% (5.686–6.413) | 13.100% (12.700–14.800) | 16.415 | 56.74 MB | **Fail**: over 2.5% average |
| Settings used then closed | 0.390% (0.386–0.580) | 0.900% | 2.953 | 33.70 MB | **Fail**: +0.172 percentage points over menu-bar median |

- Snapshot commit maximum across valid formal runs was 1.890 ms, within the 2 ms provisional gate.
  Quick Panel disk sampler boundaries reached 40.689 ms and process scans reached 125.660 ms;
  SwiftUI/Animation Hitches evidence is still required before assigning frame causality.
- The valid settings-closed runs have zero preview/process/sensor/fan counters, but CPU and retained
  footprint remain above menu-bar-only.
- A short, non-gating coverage matrix exercised gauges and every settings destination. It exposed
  8.970% gauges CPU, 6.987% Menu Bar settings CPU, and 14.678% Popover settings CPU; formal traces
  remain required.
- The lifecycle smoke completed exactly 100 panel/settings cycles. Footprint grew from 17.08 MB to
  54.92 MB (+37.84 MB; peak 85.42 MB), so the +5 MB gate fails.
- The README's `0.3–0.5% / ~20 MB` claim is supported only for the formal menu-bar idle state. It is
  not a valid claim for a visible full Quick Panel.

#### Agent boundary, compatibility, and legal decisions

- Upstream is pinned to `erha19/ping-island`
  `da130d679e830894240e926184d29751dfd2def1` (v0.25.2).
- `scripts/run_agent_compatibility_spike.sh` typechecks representative models, Claude/Codex parsers,
  thread snapshot, association store, and usage cache for `arm64-apple-macosx12.0` in Swift 5 mode.
  The only proven incompatibility in the selected slice is a macOS 13 multi-character
  `String.split`; `components(separatedBy:)` restores macOS 12 compatibility. Evidence:
  [Agent compatibility spike](evidence/wp0/agent-compatibility-spike.md).
- Decision: retain macOS 12; first Agent release slice is Claude + Codex Agent Core without Island
  UI; later providers/remote/tmux/focus/mascot/presentation remain in final parity scope.
- Decision: selected Apache-2.0 source reuse is allowed only with retained LICENSE/NOTICE and N1KO
  modification markers; product-facing identity remains N1KO-only.
- Generated file inventory covers all 452 pinned files with no blank/invalid dispositions: reuse 21,
  adapt behind protocol 75, rewrite 62, exclude until parity 294. License/resource disposition:
  Apache-2.0 361, OFL-1.1 2, unproven asset rights 87, legal attribution 2. See
  [boundary freeze](wp0-boundary-freeze.md) and
  [file inventory](wp0-upstream-file-inventory.tsv). No upstream source or asset entered the
  shipping target in WP0.

#### Verification and open gates

- Command Line Tools debug/release builds and `./build_app.sh --native --smoke` pass. Full Xcode
  executed 20 XCTest tests with 0 failures and 1 expected skip (installer DMG not mounted), including
  both new performance-diagnostics tests. Plist/localization lint, shell syntax, the native helper
  warning build/JSON check, `git diff --check`, and the shipping-path private-API/branding scans pass.
- One valid optimized 600.859-second Time Profiler trace completed and exported 35,351 time-sample
  rows. It is retained under `evidence/wp0/2026-07-15/xctrace-time-profiler/run-1/`.
- SwiftUI fails before recording with `Failed starting ktrace session` in attach and direct-launch
  forms. Developer Mode is disabled, but causality is not established. A formal Animation Hitches
  recording reached the time limit, then generated approximately 43 GB of logical data while saving,
  filled the APFS container, and aborted; its invalid trace was removed.
- Still required: two further Time Profiler repetitions, valid SwiftUI/Animation Hitches recordings,
  formal gauges and every settings-destination repetition, lock/screen sleep/system sleep/wake, and
  manual fan/curve/dependency-injected thermal-safety verification.

#### 2026-07-16 closeout

- Two additional optimized Time Profiler recordings completed at their time limits. Together with
  the first recording, WP0 has three valid traces lasting 600.859, 602.876, and 600.881 seconds and
  exporting 35,351, 41,716, and 40,763 time-sample rows.
- Quick Panel gauges completed three formal repetitions: median 9.842% average CPU, 20.900% p95,
  42.398 wakeups/s, and 35.69 MB final footprint. This confirms a WP1 problem; it is not hidden by
  changing the gate.
- Settings Overview completed three repetitions with 0.934% median average CPU and 2.000% median
  p95. Settings Menu Bar completed two valid repetitions (7.107% and 8.226% average CPU); the user
  stopped the third repetition and the partial artifact was discarded.
- The user explicitly directed the task to stop remaining long-running occupancy tests and continue
  to subsequent implementation. The unrun settings repetitions, SwiftUI ktrace failure, Animation
  Hitches storage failure, and manual sleep/fan/thermal matrices remain known risks and are not
  described as passing evidence. They must be revisited before release hardening or if a WP1 change
  touches the corresponding lifecycle/safety path.

The five explicit WP0 gates are satisfied: benchmarks are repeatable, the resource claim is scoped
to menu-bar idle and corrected elsewhere, the macOS 12 decision is explicit, all 452 upstream files
have ownership/license dispositions, and roadmap evidence is updated. This WP0 closeout handed the
roadmap to WP1, which is now also complete.

## WP1 — Monitoring performance foundation

Status: **Complete**

### Deliverables

1. Converge settings and Quick Panel lifecycle under one presentation coordinator.
2. Remove private settings-preview timers and all identity-token forced refreshes.
3. Close the Quick Panel through one state transition before opening settings.
4. Preserve and reuse the Quick Panel Hosting Controller instead of clearing it on close.
5. Introduce monotonic-deadline `SamplingPlan` scheduling.
6. Move CPU, memory, network, GPU, and disk acquisition away from the main actor.
7. Keep SMC/IOHID serialization and fan safety independent from presentation visibility.
8. Return one immutable, equatable module snapshot and commit coherent generations.
9. Replace routine `/bin/ps` sampling with libproc deltas and correct memory ranking.
10. Convert bounded histories to ring buffers and derive pixel-aware chart views.
11. Add lock, screen sleep, user-session, low-power, wake-grace, and occlusion policy.

### Gates

- All behavioral contracts in `01-audit-findings.md` remain unchanged.
- Initial performance gates are met or a documented root-cause trace proves why a gate must be revised.
- No hidden settings/panel display work remains after teardown.
- Same-generation menu bar and Quick Panel values match exactly.
- Top CPU and memory process lists match an independent ten-minute comparison fixture.
- Wake resets rate baselines and produces a full refresh within two seconds.
- Fan manual/curve/safety tests pass.

### Evidence

Implementation and verification completed on 2026-07-16; full record:
[WP1 results](evidence/wp1/2026-07-16/results.md).

- `PresentationCoordinator` is the sole owner of Quick Panel/Settings transitions. It closes the
  panel before opening settings and retains one Quick Panel hosting controller across closes. The
  SwiftUI `Settings` scene was removed so it cannot create a second settings authority.
- Settings Menu Bar preview no longer has its two-second timer or `.id` refresh token. It renders
  the shared display snapshot. Settings visibility is explicit and stops when the window tears down.
- `SamplingPlanner` uses `DispatchTime` deadlines. CPU, memory, network, GPU, disk I/O and volume
  reads run on utility queues; module snapshots are immutable/equatable and one main-thread batch
  publishes an equatable display generation. SMC/IOHID/fan paths retain their serial queues and
  remain planned independently of presentation suspension.
- Routine process sampling uses `proc_listallpids`, `proc_pid_rusage`, per-PID nanosecond deltas and
  physical footprint; `/bin/ps` remains compatibility fallback only. CPU and memory ranks are
  independently sorted over the complete sample set.
- Short and persisted histories use fixed-capacity ring buffers. Charts peak-downsample to their
  actual pixel width.
- Public lifecycle notifications cover screen sleep/wake, session active/inactive, low-power,
  thermal and occlusion state. Wake/session resume resets network/disk rate baselines, establishes a
  two-second monotonic grace window and requests a full refresh.
- A 601.063-second independent libproc-versus-`/bin/ps` comparison retained 283 samples (94.3% of
  the nominal 300 at a two-second interval). Median Top-10 overlap was 0.8 for CPU and 0.6 for
  memory, above the 0.3/0.5 acceptance thresholds. The original command wrote valid evidence but
  exited on an obsolete exact-sample-count assertion; the harness now accepts at least 90% coverage,
  and a fresh 10.185-second calibration passed with 0.9/0.7 overlap.
- A direct surface test constructs the menu-bar render input from the same immutable Quick Panel
  snapshot and asserts identical generation ID, CPU, GPU, memory, battery and network values.
- Public sleep/wake notifications are wired through the production lifecycle policy. A real general
  acquisition recovery resets network/disk rate baselines and committed a coherent full generation
  in 0.010 seconds in the final suite; concurrent wake requests coalesced without losing completion
  in 0.025 seconds. Physical machine sleep was deliberately not forced during an interactive run
  and remains a release-hardening hardware matrix item.
- Manual-mode cancellation, curve interpolation/bounds, and the 95 C thermal-safety cancellation
  path pass through the dependency-injected fan boundary. Automated verification did not issue a
  privileged hardware write.
- `swift test`: 40 tests, 0 failures, 2 expected skips (installer DMG not mounted and the opt-in
  sustained comparison omitted from the default suite). The opt-in 10-minute comparison and
  post-fix calibration pass their semantic gates.
- `swift build`, plist/localization lint, `git diff --check`, shipping private-API scan and
  `./build_app.sh --native --smoke` pass. The final release smoke idle sample was 0.3% CPU; this
  instantaneous value is not treated as a baseline.
- The retained formal WP0 trace attributes most visible Quick Panel cost to the SwiftUI/AppKit
  presentation tree rather than WP1 acquisition. A scoped 30-second post-change cards run measured
  5.285% average CPU, 13.900% p95, 20.679 wakeups/s and 45.95 MB footprint. Because it is only one
  short run after a five-second warm-up, it is diagnostic rather than a replacement for the formal
  three-run baseline. The original 2.5% visible-surface target remains assigned to the WP2 rebuild;
  see [root-cause disposition](evidence/wp1/2026-07-16/performance-root-cause.md).

Every listed WP1 gate now has automated, retained, or root-cause evidence at the available safe
boundary. No additional long-running Menu Bar occupancy test was performed. Physical sleep/lock and
privileged fan writes remain explicit WP6 hardware checks, not claims of hardware execution in WP1.
WP1 is Complete and WP2 is the sole **Next** package.

## WP2 — Native UI, motion, and settings foundation

Status: **Complete**

### Deliverables

1. Introduce N1KO color, typography, spacing, surface, and motion tokens.
2. Replace the dual settings authority with one native window/router.
3. Split settings into scoped panes and domain preference stores.
4. Implement control-level search and restored last destination.
5. Rebuild Quick Panel around a health summary and stable module rows with at most one expanded detail.
6. Replace live-root previews with noninteractive preview models using the shared snapshot store.
7. Animate only user intent and discrete state; remove repeating telemetry animation.
8. Implement Reduce Motion, Increase Contrast, Differentiate Without Color, VoiceOver descriptions, chart equivalents, and full keyboard navigation.
9. Add confirmation and explicit target naming for destructive process/fan actions.

### Gates

- One hundred Quick Panel cycles preserve controller identity and have no first-frame size jump or tile cascade.
- There is exactly one Settings window across every entry point.
- Hidden/idle UI has no sustained Core Animation work for 60 seconds.
- Preview controls cannot invoke live application actions.
- No content text below 10 pt; standard body is approximately 13 pt.
- Accessibility and keyboard scenarios in the target architecture pass.
- English, Simplified Chinese, and Traditional Chinese layouts pass at the supported minimum window size.

### Evidence

Implementation and verification completed on 2026-07-16; full record:
[WP2 results](evidence/wp2/2026-07-16/results.md).

- The native Quick Panel now uses deterministic stable rows and one disclosure. Three optimized
  60-second runs measured 0.844%, 0.802% and 0.832% average CPU (0.832% median), below the 2.5%
  target and 86.0% below the formal WP0 median. Every run retained a Time Profiler trace and valid
  visible end state.
- One AppKit Settings window/router and one detached-when-hidden hosting tree serve Settings and
  About. Tests preserve their identities for 100 cycles; the measured steady-state 100-cycle
  footprint growth is 1.75 MB after ten uncounted warm-up cycles, below the +5 MB gate.
- A retained 60-second hidden run has no Settings preview or Quick Panel counter and no SwiftUI
  renderer/layout stack. Average CPU was 0.242% and footprint growth was 0.95 MB.
- The Settings Quick Panel destination now renders an immutable, action-free shared-snapshot model.
  Its 30-second diagnostic average is 1.328%, versus the WP0 live-root short run's 14.678%.
- The final default suite has 48 tests, zero failures and two expected skips. It directly covers
  router persistence/control search, shared preference authority, one-window identity, deterministic
  geometry/disclosure, action-free preview data, chart equivalents, motion/type bounds, fan safety,
  and the three localization bundles at 900 by 600.
- Localization/catalog lint, source font/animation scans, shipping private-API scan,
  `git diff --check` and the native Release smoke build pass. No Menu Bar occupancy test was run.
- No upstream Agent source, asset, dependency or license obligation entered WP2. Existing preference
  keys remain compatible; `settings.lastDestination` is the only new persisted key and the obsolete
  presentation-style key remains as a no-op until the WP5 versioned migration.

## WP3 — Agent Core

Status: **Complete**

### Deliverables

1. Add an isolated `N1KOAgentCore` target and N1KO-owned `AgentSessionCoordinator`.
2. Port event/session/provider/phase models and lifecycle store.
3. Port Claude and Codex ingestion, parsing, app-server/rollout support, association, usage, intervention, and completion semantics behind protocols.
4. Introduce N1KO-owned runtime paths, diagnostics redaction, and secure socket policy.
5. Port relevant upstream logic tests and add N1KO lifecycle/shutdown tests.
6. Integrate Agent energy/lifecycle policy without changing monitor sampling ownership.
7. Expose immutable Agent snapshots without adding Island UI.

### Gates

- Claude and Codex sessions can be received, merged, restored, completed, archived, and attention-marked without UI.
- Approve/deny/answer response routing has authenticated ownership and focused tests.
- App shutdown closes socket, watchers, tasks, and subprocesses.
- Agent enabled but idle does not materially change monitor-only idle CPU or maintain a display link.
- No upstream AppDelegate, updater, settings window, telemetry, or product identity enters the N1KO target.

### Evidence

Implementation and verification completed on 2026-07-16; full record:
[WP3 results](evidence/wp3/2026-07-16/results.md) and
[migration/license checklist](evidence/wp3/2026-07-16/migration-license-checklist.md).

- `N1KOAgentCore` is isolated from presentation, settings, updater, monitor sampling, and the
  upstream application shell. N1KO's `AgentSessionCoordinator` owns immutable snapshot publication,
  Claude/Codex parsing, protocol ingress, association/usage/lifecycle persistence, energy state,
  authenticated response routes, and shutdown.
- Real socket tests prove 0700/0600 permissions, peer UID, install-secret rejection, and N1KO paths.
  Approve/deny/answer tests prove provider/session/request/owner/capability matching. Graceful app
  exits recorded socket=1, watcher=1, and remaining=0.
- `swift test` executes 69 tests with zero failures and two expected skips; 21 tests are Agent Core
  tests. macOS 12 whole-module typecheck, lint, shell syntax, private-API/shell/display-link/identity
  scans, `git diff --check`, native Release assembly, ad-hoc bundle verification, and native smoke
  all pass. The smoke CPU sample was 0.0%.
- Three same-build 58-second runs measured Agent-disabled 0.244% median average CPU and Agent-enabled
  0.274%, a +0.030 percentage-point delta; median wakeups were 2.362 versus 2.328/s and every enabled
  measurement window had zero ingress. No Agent-owned display link exists.
- An initial invalid restore replay reached approximately 10% CPU and a 225.30 MB peak; it is retained
  as failure evidence. Lifecycle projection, idempotent replay, and bounded first-line + 1 MiB tail
  reading fixed it. Final-code clean restore loaded 200 sessions at 0.308% CPU, 24.30 MB final
  footprint, and 25.30 MB peak.
- At the WP3 gate, modified Apache-derived core files carried notices and the exact 201-line license
  shipped in the app bundle; no upstream UI had entered that package. WP4 later migrated the pinned
  UI source with the expanded LICENSE/NOTICE record described below.

## WP4 — Agent Island and fullscreen behavior

Status: **Complete**

### Deliverables

1. Implement `AgentSurfaceCoordinator`, `DesktopIslandPanel`, and `FullscreenRevealPanel`.
2. Implement the public-API fullscreen environment state machine and display-coordinate normalization.
3. Migrate the pinned Ping-Island compact, hover-expanded, click-expanded, intervention,
   session-list, completion, usage, and detached view/controller/model source behind N1KO snapshots
   and authorities while retaining N1KO identity and excluding unproven upstream assets.
4. Add deliberate top-edge reveal, Escape/pointer exit dismissal, wake reconciliation, and target-screen selection.
5. Add Agent Center and presentation settings to the unified window.
6. Add the multi-display AppKit UI harness and transition logging.

### Gates

- Every acceptance gate and matrix item in `03-fullscreen-window-design.md` passes.
- Native fullscreen has zero baseline flash in 100 repeated cycles.
- Pseudo-fullscreen behavior has measured, documented latency.
- Agent UI uses N1KO tokens and Reduce Motion policy.
- No duplicate session ownership or half-old/half-new snapshot composition.

### Evidence

The original fullscreen/ownership implementation was verified on 2026-07-16; its retained record is:
[WP4 results](evidence/wp4/2026-07-16/results.md) and
[migration/license checklist](evidence/wp4/2026-07-16/migration-license-checklist.md).

- The existing `PresentationCoordinator` owns one `AgentSurfaceCoordinator`. It consumes WP3's
  immutable Agent snapshot and shares one projection with N1KO-native compact, expanded,
  intervention, completion, session-list, usage, and Agent Center views. Approve/deny/answer stays
  on WP3's authenticated provider/session/request/owner/capability route.
- The production desktop and reveal panels are separate `N1KOWindowCore` types. A retained
  calibration rejected `.canJoinAllSpaces + .fullScreenNone` after it exposed 3/3 desktop samples
  in native fullscreen. `.moveToActiveSpace + .fullScreenNone`, with no
  `.fullScreenAuxiliary`, then completed 100 real native enter/exit cycles with 0/300 fullscreen
  desktop-panel samples, zero restore failures, and zero reveal construction without dwell.
- The public-API state machine uses display UUID/Quartz normalization, bounded generation-cancelled
  retry samples, optional permission-gated background AX evidence, 180 ms top-edge dwell,
  pointer/Escape/Space/sleep/session dismissal, wake reconciliation, and target-screen fallback.
  The live pseudo-fullscreen result was 16.105 ms to hide and 87.536 ms to stable classification.
- The synthetic AppKit/Quartz matrix covers notched/notchless, mixed/two external, horizontal,
  vertical, scaled, menu-display reassignment, application modes, helper owners, lifecycle, rapid
  transitions, and disconnected targets. Physical WindowServer evidence used the attached
  notchless 5K external display; mixed/notched/separate-Spaces physical matrices remain explicit WP6
  hardware risks rather than unverified claims.
- A final optimized hidden-surface run measured 0.251% average CPU, 0.800% p95, 2.273 wakeups/s,
  +1.66 MB footprint, and zero ingress/composition/global-monitor/retry activity. A short-warm-up
  restore run and a main-thread AX diagnostic are retained as invalid/failure evidence; final code
  skips unauthorized AX and samples evidence off the main thread.
- `swift test` runs 81 tests with zero failures and three expected skips; the default-skipped live
  pseudo gate was run separately and passed. `swift build`, localization/plist lint, shell syntax,
  `git diff --check`, ownership/private-API/branding/motion/type scans, Release native assembly,
  strict ad-hoc verification, and native smoke pass. The final smoke sample was 0.0% CPU and the
  binary remains `minos 12.0`.

The fullscreen, ownership, response-routing, performance, build, and compatibility evidence above
remains valid. After the user rejected both the generic card and the N1KO-authored corrective shell,
the 2026-07-17 correction changed strategy from visual reconstruction to a pinned source-level UI
migration. Production desktop/reveal windows now host `NotchViewController + NotchView`; the floating
surface hosts `DetachedIslandWindowController + DetachedIslandPanelView`. The migration comprises 72
Swift files: 41 byte-identical same-path files, 24 adapted same-path files with modification markers,
and 7 N1KO boundary adapters. It runs the pinned route, list/detail/question/completion, mascot,
detachment, sizing, event, and energy behavior while preserving the one-owner architecture.

The prior detail-data work remains active: bounded 80-item history, rich tool association,
five-hour/seven-day quota windows, full completion policy, literal tmux follow-up, mascot overrides,
and confined CESP/OpenPeon packs. Pinned focus actions now resolve back to the N1KO capability owner.
The pinned settings action now reaches N1KO's sole Agent Center on the first click after launch. The
source-extracted behavior/display, sound, and mascot settings are hosted there with auto-hide,
suppression, separate completion/compaction auto-open, collapse, notch-or-floating presentation,
density/size/content/usage controls, five event mappings, three sound modes, previews, OpenPeon/CESP
discovery/import, and per-client mascot/status controls. Presentation-mode changes drive the existing
N1KO window owner. With the user's explicit
resource approval, all 13 pinned WAV files are bundled byte-identically and covered by the retained
Apache license/NOTICE. Fonts, product icons/screenshots, branding, and other unproven resources remain
excluded. The public-API desktop/reveal fullscreen structure is unchanged. Current direct evidence is
[the pinned source-parity record](evidence/wp4/2026-07-17/ping-island-source-parity.md) and its
[migration/license checklist](evidence/wp4/2026-07-17/migration-license-checklist.md); the earlier
[parity correction record](evidence/wp4/2026-07-16/ping-island-parity-correction.md) is retained as
rejected/intermediate history.

Current verification: `swift test` executed 129 tests with 3 expected skips and 0 failures; the WP4
suite executed 28 with one opt-in live skip and 0 failures. Source-view captures, controller-host
tests, Release native smoke, localization uniqueness, identity, ownership, public API, minos 12.0,
signature, legal-bundle, and diff gates pass. No Menu Bar occupancy matrix or long soak was run.

Those formerly open boundaries were closed on 2026-07-21: N1KO now owns Claude pseudo-terminal
launch/input/termination, an authenticated Codex app-server stdio child for native threads and
non-tmux follow-up, per-session termination ownership, and public process-tree/tmux focus
suppression. Touched Swift 6 isolation warnings were removed. The full 138-test suite, installed
Codex acceptance, fake-Claude runtime, native Release/smoke and WP6 release gate pass. Direct record:
[WP4 closure evidence](evidence/wp4/2026-07-21/results.md). The user's explicit completion and
release request resolves the former release-decision acceptance blocker; unavailable physical and
manual matrices remain WP6 risks rather than being represented as passes.

## WP5 — Full integration parity and migration

Status: **Complete**

### Deliverables

1. Add remaining provider/client integrations in focused slices: Gemini, Qwen, Kimi, Hermes, OpenCode, Pi, Qoder/CodeBuddy families, and other audited supported clients.
2. Add terminal/IDE focus, tmux, remote/SSH, optional surface/mascot capabilities according to the recorded product slicing decision.
3. Implement versioned N1KO preference migration and optional legacy Agent-app import.
4. Implement managed-hook takeover with backups, conflict detection, proof event, rollback, and removal ledger.
5. Rename every product-facing bridge, marker, path, socket, subsystem, executable, asset, feed, and link to N1KO identity.
6. Retain only N1KO UpdateController and add active-session install deferral if required.

### Gates

- Provider-by-provider parity matrix passes.
- Hook installation, repeated installation, upgrade, downgrade, conflict, and rollback are idempotent and preserve unrelated user configuration.
- Old and new applications running together are detected and cannot repeatedly overwrite hooks.
- Remote/socket connections from an invalid user are rejected.
- Product-facing brand scan is clean except approved legal and temporary migration allowlists.
- Minimum deployment target and permissions remain explicit.

### Evidence

Implementation and verification completed on 2026-07-16; full record:
[WP5 results](evidence/wp5/2026-07-16/results.md),
[provider parity matrix](evidence/wp5/2026-07-16/provider-parity-matrix.md), and
[migration/license checklist](evidence/wp5/2026-07-16/migration-license-checklist.md).

- The N1KO-owned registry contains 21 audited client profiles, with a one-to-one reproducible
  fixture matrix, 17 managed JSON/TOML/plugin shapes, and two explicit runtime-only profiles that
  reject configuration writes. A real separately built bridge probe reached Gemini-aware ingress
  through the private authenticated Unix socket.
- Terminal/IDE focus uses public APIs; validated tmux execution does not use a shell. SSH is an
  opt-in typed command-plan boundary with mandatory fingerprint and strict host checking. SF
  Symbols are the only optional companion resources; all third-party visual/audio assets remain
  excluded.
- Schema 2 settings migration writes a private exact defaults backup before mutation and is
  idempotent. Optional legacy import is explicit, read-only, and limited to associations,
  allowlisted profile selection, and aggregate usage/cache; transient window state and secrets are
  excluded.
- Managed-hook takeover records exact per-file backups and hashes, stages N1KO entries, runs a
  three-second-bounded real bridge proof, rechecks for concurrent changes, and removes exact legacy
  references only after proof. Repeat, upgrade, downgrade, conflict, rollback, removal, and user
  replacement paths have direct tests. A live-owner lease prevents legacy/new reinstall loops.
- Product identity scans pass outside legal/modification comments and the two temporary migration
  files. The main and bridge binaries are N1KO-identified and `minos 12.0`; no private CGS/SLS or
  SkyLight shipping symbol was introduced. Apache, complete Sparkle, and SMCKit license texts are
  bundled.
- The scoped native `agent-core-idle` measurement recorded 0.195% average CPU, 0.800% p95,
  2.121 wakeups/s, +1.11 MB footprint, and zero ingress/surface work with 200 restored sessions.
  This was a WP5 integration gate, not a repeat of the discontinued Menu Bar occupancy matrix.
- `swift test` executes 99 tests with zero failures and three expected skips. `swift build`, plist
  and three-locale lint/sync, shell syntax, `git diff --check`, identity/private-API/ownership scans,
  native Release assembly, strict deep signature verification, and native smoke pass.

No live third-party client matrix, real SSH host, macOS 12/Intel hardware, different-user account,
or 24-hour soak is claimed; those remain explicit WP6 release-hardening risks. On 2026-07-21, Ping
Island v0.26.0 (`c9148fc6a66a98f62dc1cac8fde415c2be9f2233`) was audited selectively: the unchanged
Island UI and assets remain on the reviewed mapping, Qoder CN desktop/CLI profiles were added, and
the Qwen same-workspace fix was verified as already satisfied. See
[v0.26.0 audit](evidence/wp5/2026-07-21/upstream-v0.26.0-audit.md).

## WP6 — Release hardening

Status: **In Progress / Next (residual long-duration and manual evidence)**

### Deliverables

1. Run 24-hour monitoring-only and Agent-enabled soak tests.
2. Run performance, energy, memory-growth, sleep/wake, accessibility, localization, permissions, migration, fullscreen, and security matrices.
3. Finalize third-party licenses, NOTICE, modified-file markers, and bundled-resource rights.
4. Finalize diagnostics redaction and user-facing privacy/permission copy.
5. Update README claims only from measured release evidence.
6. Produce release notes and rollback instructions. Do not publish without explicit user authorization.

### Gates

- `swift build`, complete test suite, `plutil -lint`, `git diff --check`, and native smoke pass.
- No unresolved requirement in the prior work packages lacks direct evidence.
- No 24-hour memory/task/subscription growth outside the documented budget.
- All product-facing upstream identity has been removed; legal attribution remains correct.
- Release artifacts are not produced or published until separately authorized.

### Evidence

Implementation and verification are in progress; current records:
[2026-07-21 release-candidate results](evidence/wp6/2026-07-21/results.md),
[WP6 in-progress results](evidence/wp6/2026-07-16/results-in-progress.md),
[environment/evidence boundary](evidence/wp6/2026-07-16/environment-inventory.md),
[rollback runbook](wp6-rollback-and-recovery.md), and
[blocked release-notes draft](wp6-release-notes-draft.md).

- Added an opt-in, isolated, interrupt-safe 24-hour runner and analyzer for the required independent
  monitoring-only and Agent-enabled soaks. It measures cumulative CPU/wakeups, RSS/footprint,
  footprint growth/slope, threads, FDs, sockets, bounded history, Agent ingress resources,
  tasks/subprocesses, response routes, observers, surface resources, and lifecycle notifications.
  Short runs are structurally labelled calibration and cannot produce `RELEASE_PASS`.
- Added count-only Agent ownership snapshots, actual Codex directory-watch counts, isolated history
  output, diagnostic log/export redaction, 0700/0600 export permissions, an archive privacy
  manifest, and user-facing local/no-auto-upload copy. No monitoring, history, alert, fan-control,
  or thermal-safety cadence was changed.
- Both 20-second calibration measurements passed their short-run mechanics/resource budgets. The
  monitoring-only sample averaged 0.180% CPU and 2.111 wakeups/s with +0.125 MB footprint; the
  Agent-enabled sample averaged 0.103% CPU and 2.056 wakeups/s with -0.219 MB footprint and exactly
  200 isolated synthetic sessions. All thread/FD/socket and internal Agent resource deltas were
  non-growing. These values are calibration only, not release claims.
- `swift test` executes 104 tests with zero failures and three expected environment skips. Native
  arm64 Release assembly and smoke pass (0.3% one-sample idle CPU); localization uniqueness,
  complete/bundled legal files, modification markers, N1KO identity, sole-owner invariants,
  CGS/SLS/SkyLight source and symbol exclusion, strict ad-hoc signatures, both binary minos 12.0,
  and diff hygiene pass.
- A pre-measurement run started at `11:01:40Z` and was deliberately interrupted when the missing
  cumulative-energy column was detected. The `11:05:50Z` run retained two real sleep/wake cycles,
  then a live permission audit found history at 0644 inside a 0700 evidence parent. It was stopped,
  history directory/file permissions were hardened to 0700/0600 with tests, and the rebuilt final
  candidate started its monitoring-only 24-hour soak at `2026-07-16T11:36:37Z` in
  `evidence/wp6/2026-07-16/soaks/monitoring-only/20260716T113637Z`. Measurement began at
  `11:38:44Z`; the first complete interval and private-history check passed. The run was then
  intentionally interrupted after 1,093 awake seconds because its Agent-disabled single-process
  setup displaced the user's normal Agent Center/Island UI. Partial data is retained, the
  Agent-enabled handoff was cancelled, and the soak harness now requires non-disruptive isolation
  before another long run. WP6 remains In Progress but is paused while WP4 is the sole Next package;
  no completion is claimed until both 24-hour runs and the remaining direct real/manual matrices
  close or are explicitly resolved as release blockers.
- During the retained `11:05:50Z` monitoring-only run, two real host sleep/wake cycles were corroborated by
  `pmset`, N1KO lifecycle logs, and wall-clock versus monotonic sample deltas. The process survived,
  history resumed without synthesizing sleeping intervals, system sleep/wake balanced 2/2, and
  disabled-Agent resource counts remained zero. Explicit lock/unlock and fast-user-switch evidence
  is still pending; see [lifecycle matrix](evidence/wp6/2026-07-16/lifecycle-matrix-in-progress.md).
- On 2026-07-21 all remaining code work and locally available automated release gates passed: 138
  tests with three explicit environment skips and installed-Codex acceptance enabled, warning-free
  build, native Release/smoke, three-locale
  lint, identity/owner/legal/sound/public-API/minos/signature/diff gates, and installed-Codex stdio
  initialization. Final isolated 30-second calibrations averaged 0.091% awake CPU / 1.57 wakeups/s
  for monitoring and 0.086% / 1.41 for Agent Core with 200 sessions, with no growing
  thread/FD/socket/Agent/surface resource count. A failed pre-fix calibration exposed hidden mascot
  animation in the headless harness; the harness now omits presentation installation only for
  `N1KO_PERF_HEADLESS=1`, leaving the product path unchanged. These are calibration results, not
  substitutes for the two 24-hour runs.
- The user explicitly authorized the v1.0.18 release with this documented evidence boundary. WP6
  remains Next after publication until both 24-hour soaks and unavailable notched/mixed-display,
  Intel/macOS 12, different-user, real-SSH, VoiceOver, lock/unlock and fast-user-switch matrices
  complete; none are represented as passed.
- v1.0.18 was published on 2026-07-21 from source commit `4ff76b1`. GitHub Actions run
  `29799932353` passed the Xcode 15.4 arm64+x86_64 build, DMG verification, signed Sparkle appcast
  generation/publication, release-note resolution, and GitHub Release creation. The workflow wrote
  the generated appcast to main as `c348a93`. Earlier failed attempts exposed and then closed
  Xcode-15-only source compatibility issues; they did not publish a partial Release.
