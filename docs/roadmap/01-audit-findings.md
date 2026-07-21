# 01 — Audit findings

Audit date: **2026-07-15**

N1KO-STATE checkout: **`09cde29c24d20f8b97f0fd2995a686fac0cb3ab7`**

Audit type: code inspection plus read-only sampling of the installed v1.0.17 application.

## Executive conclusion

The high resource use is not explained by the desired monitor freshness alone. The dominant design problem is that acquisition, publication, rendering, window visibility, and animation lifecycles are coupled. Invisible or logically closed presentation paths can keep work alive; a single sample can fan out through multiple observable objects and full-view snapshots; continuous telemetry changes repeatedly restart SwiftUI animations.

The UI problem has the same root shape: multiple window authorities, reconstructed view trees, competing visual surfaces, and motion attached to raw data changes rather than to user intent.

The safe optimization sequence is therefore:

1. stop erroneous invisible presentation work and stale visibility state;
2. separate acquisition, safety, publication, and rendering;
3. reduce fixed sampler cost without changing semantic cadence;
4. redesign the UI on top of stable ownership and snapshots;
5. add Agent capabilities only after the performance and presentation foundation is measurable.

## Runtime evidence

One diagnostic run used the installed app after roughly 22 hours of uptime with a two-second refresh setting, CPU/GPU/memory in the menu bar, all Quick Panel modules enabled, and alerts disabled.

- Twenty seconds of process CPU-time growth measured about **1.71 seconds**, or roughly **8.55% of one core**.
- `vmmap` reported an approximate **79 MB footprint** and **101.3 MB peak**.
- A ten-second sample included approximately **80 ms in SensorMonitor/IOHID work** and about **2 ms in fan reads**.
- A no-visible-window observation still showed settings/menu-bar preview and image-rendering call paths, together with sensor/fan refresh activity.
- A separate sample exposed sustained SwiftUI DisplayLink activity while the panel was open, with CPU commonly moving through the mid-single to low-double digits.

These are diagnostic observations, not a final release benchmark. WP0 must reproduce every scenario using an optimized build, a known settings fixture, warm-up time, three repeated recordings, and signposts. The README's historical `0.3–0.5% CPU / ~20 MB` statement must be revalidated before it remains a product claim.

## Performance root causes

### P0 — Invisible presentation work can remain alive

- `MenuBarPreviewView` in `Sources/N1KOState/Views/Settings/SettingsView.swift` owns a two-second common-run-loop timer and changes an identity token to force preview reconstruction and bitmap generation.
- The app declares a SwiftUI `Settings` scene in `Sources/N1KOState/App/N1KOStateApp.swift` and also creates a manual settings window in `Sources/N1KOState/Views/Settings/SettingsWindowController.swift`.
- The two authorities make visibility, occlusion, selected page, and teardown difficult to reason about. A closed or hidden settings surface can leave preview work participating in layout or rendering.
- Opening settings from the Quick Panel does not first force every path through one close transition. `popoverOpen` can therefore become a stale sampling input.

Required correction: one settings/window authority, one presentation state coordinator, no private preview timer, and explicit visible/occluded lifecycle gates.

### P0 — Sampling work shares the main thread with SwiftUI

`MonitorHub.tick` is driven by a main-thread timer. The following work is synchronously reached from that path:

- CPU Mach calls in `CPUMonitor`;
- memory host statistics and swap sysctl in `MemoryMonitor`;
- `getifaddrs` enumeration in `NetworkMonitor`;
- IORegistry property work in `GPUMonitor`;
- disk I/O registry and volume work in `DiskMonitor`.

Each individual call may be short, but the combined periodic workload competes with AppKit event handling, view layout, menu-bar bitmap creation, and animations.

Required correction: the main actor builds a `SamplingPlan`; dedicated sampler executors perform acquisition; a completed immutable generation is committed once on the main actor.

### P1 — Publication fan-out and incoherent UI domains

- CPU, memory, network, GPU, disk, sensors, battery, and fans publish through their own observable objects.
- `MonitorHub` also publishes `MonitorDisplaySnapshot`.
- Gauge views use the snapshot while card views can observe individual monitors.
- Sensor and fan completion changes multiple `@Published` properties separately.
- Async module results can miss the current aggregate commit and appear a tick later in snapshot-based surfaces.

Required correction: a module returns one `Equatable` module snapshot per generation. Menu bar, Quick Panel, cards/gauges, and settings preview derive from the same committed store.

### P1 — Process sampling is expensive and semantically wrong

`Sources/N1KOState/Monitors/ProcessMonitor.swift` periodically forks `/bin/ps`, parses text, keeps the CPU-sorted leading rows, and derives memory leaders from that subset. A low-CPU, high-memory process may never enter the memory ranking.

Required correction: use public libproc APIs (`proc_listallpids`, `proc_pidinfo`/`proc_pid_rusage`) with per-PID CPU-time deltas and an explicit compatibility fallback. This removes repeated fork/exec and fixes the memory Top list.

### P2 — Avoidable history and graph allocation

- Short histories use `append` plus `removeFirst`.
- Long history arrays are copied out of dictionaries, mutated, and stored again.
- some charts process more points than their physical pixel width can display.
- network up/down changes can independently repeat the same history derivation.

Required correction: fixed-capacity ring buffers and a display-only downsample derived from the untouched raw history.

### P2 — Incomplete sleep, lock, and occlusion policy

The app handles wake behavior but lacks one coherent policy for screen sleep/wake, user-session resign/become-active, app/window occlusion, Quick Panel visibility, Agent activity, low-power mode, and safety requirements.

Required correction: a policy object distinguishes display-only work, history acquisition, alert acquisition, fan safety, active Agent events, and discretionary background work.

## UI and UX root causes

### Two settings-window authorities

`N1KOStateApp.swift` and `SettingsWindowController.swift` can create different settings-window lifecycles. About routing also behaves like a special case rather than a first-class destination.

### Quick Panel reconstruction

`AppDelegate.popoverDidClose` clears the content view controller. Every new opening reconstructs the SwiftUI tree, replays tile/ring entry animations, resets local state, and waits for geometry-driven height feedback. This explains the perceived first-frame jump and inconsistent opening motion.

### Raw telemetry drives animation

`GaugeGridView.swift`, `Gauges.swift`, module cards, core bars, and text details attach spring or implicit animations to values that change every sample. Overlapping animations can keep the display link active even though the user has not initiated a transition.

### Competing surface systems

The system Popover already provides a material, contour, and shadow. The content adds its own opaque surface and several custom card levels. Settings introduces another set of dark surfaces, pills, and groups. The result feels less native despite using SwiftUI materials.

### Unsafe live settings preview

The settings preview embeds the actual `PopoverRootView`. Real Settings and Quit controls remain part of the hierarchy, and the preview maintains a separate sampling/rendering path. A preview must be a noninteractive `PreviewModel` projection, never the live application root.

### Accessibility and motion gaps

- Some gauge/detail text is below a comfortable macOS content size.
- Colors can be the only status channel.
- Custom charts lack equivalent current-value/range/trend accessibility.
- destructive process actions need explicit confirmation and a named target.
- Reduce Motion does not centrally suppress spring, scale, offset, blur, or repeating animation.

## What must not be optimized away

The following are functional contracts, not expendable overhead:

- the selected live sampling profile and freshness semantics;
- 30-second long-history sampling and 24-hour retention;
- current alert thresholds and evaluation behavior;
- manual fan mode and target ownership;
- fan-curve cadence and recovery;
- thermal-safety override and automatic reset behavior;
- menu bar and panel value consistency;
- immediate post-wake refresh with correct network/disk delta baselines.

Optimization should make these contracts cheaper and more deterministic, not weaker.

## Initial performance gates

WP0 may refine these after reproducible traces, but it must not silently loosen them.

- Menu-bar-only background: average CPU at or below **0.5%**, one-second p95 at or below **1%**.
- Settings hidden after use: no preview renders, process scans, or display-only sensor/fan scans; CPU increment at or below **0.1%** over menu-bar background.
- Reproduction of the audited high-cost state: at least **60% CPU reduction**.
- Full Quick Panel at two-second refresh: average CPU at or below **2.5%**.
- Main-actor snapshot commit p95 at or below **2 ms** and no sampler-caused frame over **16.7 ms**.
- One hundred open/close cycles: window, timer, subscription, and task counts return to baseline; footprint grows by no more than **5 MB**.
- Agent subsystem enabled but idle: no continuous display link and no polling loop that materially changes the monitor-only idle baseline.

See [research-sources.md](research-sources.md) for the Apple and open-source basis behind these conclusions.
