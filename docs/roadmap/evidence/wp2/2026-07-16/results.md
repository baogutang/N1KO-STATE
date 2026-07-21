# WP2 completion evidence — 2026-07-16

Checkout: `09cde29c24d20f8b97f0fd2995a686fac0cb3ab7` plus the preserved uncommitted
WP0/WP1 implementation and this WP2 implementation. Machine and fixture match the retained WP0
baseline: Mac16,10, macOS 15.7.7, native arm64 Release, all modules enabled, two-second profile.

## Implemented

- Added the Calm Telemetry color, typography, spacing, surface, hit-target and motion tokens. Raw
  telemetry values no longer start springs, cascades or repeating animations; the remaining motion
  is opacity feedback and the user-requested Quick Panel disclosure.
- Kept one `AppSettings` authority and added typed domain views through `AppPreferences`; no second
  cache, defaults domain or persistence path was introduced.
- Added one settings router and control-level search index. The last valid destination is persisted,
  every indexed result routes to a concrete control anchor, and the one AppKit settings window and
  hosting tree survive Settings/About entry-point cycles. Closing detaches the tree from the window
  so it cannot render while hidden.
- Rebuilt the Quick Panel as a CPU/memory/thermal health summary plus deterministic 50-point module
  rows. At most one existing detail card can be expanded. The first body height is computed from the
  module count; no geometry preference, entrance cascade or tile state determines the first frame.
- Replaced the Settings live `PopoverRootView` with an immutable `QuickPanelPreviewModel` containing
  only display data. It has no callbacks or controller references and does not accept hit testing.
- Added VoiceOver current/range/trend chart equivalents, severity icons/text, monospaced values,
  control labels/hints, Command-F settings search, menu shortcuts, Increase Contrast strokes,
  Differentiate Without Color severity text and Reduce Motion disclosure policy.
- Added named confirmations for process termination, manual fan takeover and fan-helper removal.
  Existing automatic restoration and thermal-safety behavior remains in the controller layer.
- Raised all shipping view content text to at least 10 points and moved standard settings controls
  to the regular control size. English, Simplified Chinese and Traditional Chinese WP2 strings were
  added with matching catalogs.

## Performance and lifecycle results

All percentages are one logical CPU. The WP0 Quick Panel reference is the retained formal three-run,
approximately ten-minute median; the WP2 visible result is three optimized 60-second repetitions
with valid final state and a Time Profiler trace for every repetition.

| Scenario | Baseline | WP2 result | Disposition |
|---|---:|---:|---|
| Quick Panel average CPU | 5.933% formal median | 0.844%, 0.802%, 0.832%; **0.832% median** | 86.0% lower; passes 2.5% target |
| Quick Panel one-second p95 | 13.100% formal median | 2.100%, 1.800%, 2.300%; **2.100% median** | 84.0% lower |
| Quick Panel wakeups/s | 16.415 formal median | 3.293, 3.190, 3.466; **3.293 median** | 79.9% lower |
| Quick Panel footprint growth | not isolated in the formal table | 1.17, 1.50, 2.11 MB; **1.50 MB median** | bounded in all three runs |
| Settings Quick Panel preview average CPU | 14.678% short WP0 live-root run | **1.328%** 30-second diagnostic | live root removed; 91.0% lower |
| Settings used then hidden | 0.390% formal median | **0.242%**, 0.800% p95, 0.95 MB growth over 60 seconds | no preview/panel counters |
| 100 panel/settings cycles | 37.84 MB cold growth | **1.75 MB steady-state growth** after 10 uncounted warm-up cycles | 100/100 complete, valid hidden end state, passes +5 MB gate |

The lifecycle investigation deliberately retains three intermediate artifacts: cold 100-cycle
growth was 24.66 MB, one-cycle-primed growth was 6.09 MB, and ten-cycle-primed growth before hosting
retention was 5.31 MB. Those runs separated framework/cache allocation from repeated Settings-tree
reconstruction. Retaining the detached hosting tree reduced the final steady-state result to 1.75 MB.
The hidden 60-second rerun then proved that retention did not reintroduce display work.

The hidden run's counter keys contain no `settingsPreviewRender` or `quickPanelUpdate`. A ten-second
stack sample has five low-frequency Core Animation commits and no SwiftUI renderer/layout stack;
those commits align with the still-required shared snapshot/menu-bar publication rather than a
display link or hidden settings renderer.

Raw summaries, counters, stack samples and traces are retained under this directory:

- `quick-panel-3x60/`
- `settings-quick-panel-preview/`
- `settings-hidden-retained-60s/`
- `panel-settings-100-cycles-retained/`
- the cold/primed lifecycle investigation directories

## Gate evidence

- Unit tests run 100 Quick Panel host close/prepare cycles and preserve one hosting identity. The
  deterministic layout test repeats the same module-count calculation 100 times, and the disclosure
  model proves that selecting a second module replaces rather than adds an expanded detail.
- Unit tests prepare/show/close Settings through Settings and About entry points 100 times and assert
  one `NSWindow`, one retained hosting controller and one persisted router destination.
- Recursive preview-model reflection finds no function value; the model holds only health and module
  projections. Shipping preview hit testing is disabled.
- Chart tests cover empty history plus current/minimum/maximum and rising/steady trend output. Source
  scans find no view font below 10 points and no animation outside disclosure/press feedback.
- The actual English, `zh-Hans` and `zh-Hant` localization bundles render the Settings root at the
  supported 900 by 600 minimum in an AppKit hosting view. Localization catalogs have identical keys.
- Process and fan safety tests continue to pass, including 95 C thermal cancellation. No privileged
  fan write was issued during verification.

## Migration and license disposition

- No upstream Agent source, asset, AppDelegate, updater, window shell, telemetry or product branding
  was migrated in WP2. No dependency was added.
- Existing N1KO defaults, module visibility/order, refresh interval, alert, fan and chart-range keys
  remain readable and keep their prior defaults. The legacy `popoverStyle` key is retained for
  compatibility even though the rebuilt Quick Panel no longer exposes dual presentation trees. The
  only new persisted value is `settings.lastDestination`.
- SMCKit MIT attribution remains visible in Settings; Sparkle and existing notices are unchanged.
  WP2 creates no Apache-2.0 reuse or NOTICE obligation and consumes none of the WP0 upstream reuse
  allowlist.
- Product-facing strings, paths and controls introduced here use N1KO-STATE identity. A shipping
  source scan finds no `CGS*`, `SLS*` or SkyLight symbol.

## Verification

| Check | Result |
|---|---|
| `swift test` | 48 tests, 0 failures, 2 expected skips |
| `./scripts/sync_localization.sh` | English, Simplified Chinese and Traditional Chinese key sets match |
| `plutil -lint Resources/Info.plist Localization/*/Localizable.strings` | Pass |
| Content-font and animation source scans | no content below 10 pt; only discrete disclosure/press feedback remains |
| Shipping `CGS*` / `SLS*` / SkyLight scan | no matches |
| `git diff --check` | Pass |
| `./build_app.sh --native --smoke` | Pass; native arm64 Release app |

The two default-suite skips remain expected: the installer DMG is not mounted and the independent
ten-minute process comparison is opt-in. No Menu Bar occupancy test was restarted.

## Completion and retained risk

Every WP2 gate has direct code, unit, localization, stack/counter or optimized runtime evidence. WP2
is **Complete** and WP3 — Agent Core is the sole next dependency-satisfied package.

Retained risks are explicit:

1. The three-repeat Quick Panel confirmation uses 60-second windows, not a second set of formal
   ten-minute runs. The margin to the 2.5% target is large and each run has a valid Time Profiler
   trace, but longer soak remains WP6 release-hardening work.
2. Full interactive VoiceOver navigation and physical keyboard focus order were structurally tested
   and rendered, but an external Accessibility Inspector/manual assistive-technology pass remains a
   WP6 release matrix item.
3. Physical sleep/lock and real privileged fan writes were not forced; those hardware scenarios
   remain WP6 checks.
4. The old `popoverStyle` preference is intentionally retained as a no-op compatibility key. Its
   final versioned removal belongs to WP5 migration, not WP2.
