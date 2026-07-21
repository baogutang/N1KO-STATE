# WP0 measurement results — 2026-07-15

## Environment and method

- Checkout: `09cde29c24d20f8b97f0fd2995a686fac0cb3ab7` plus the uncommitted WP0 probes and runner.
- Machine: Mac16,10, 10 logical CPUs, 16 GB; macOS 15.7.7 (24G720).
- Compiler/build: Apple Swift 6.1.2, optimized native arm64 Release application.
- Fixture: `Fixtures/Performance/baseline-all-modules-2s.plist`.
- Formal runs: 120-second warm-up, approximately 600 measured seconds, three valid repetitions.
- Trace backend: `sample` + `vmmap` + `proc_pid_rusage` + one-second `top` samples + signposts/counters.
- CPU time is converted from Mach absolute-time units with `mach_timebase_info` before percentage
  calculation. A two-second saturated-process calibration produced a 2.001-second CPU delta.

Full Xcode 26.3 is installed and its tests and `xctrace` run. The formal fallback results below are
kept separate from one valid Time Profiler recording; neither set is silently mixed into the other.

## Formal result summary

All percentages are one logical CPU. `median (range)` is reported across three valid runs.

| Scenario | Average CPU | 1 s p95 CPU | Wakeups/s | Physical footprint | Peak footprint | Gate result |
|---|---:|---:|---:|---:|---:|---|
| Menu-bar-only | **0.218%** (0.190–0.310) | **0.600%** (0.400–0.800) | **1.960** (1.589–2.624) | **19.67 MB** (19.33–20.64) | **20.88 MB** (19.67–21.22) | Passes 0.5% average / 1% p95; README idle claim is supported for this state |
| Quick Panel cards, all modules | **5.933%** (5.686–6.413) | **13.100%** (12.700–14.800) | **16.415** (16.391–23.483) | **56.74 MB** (51.25–58.67) | **62.09 MB** (60.17–63.66) | **Fails** 2.5% average gate |
| Settings used, then closed | **0.390%** (0.386–0.580) | **0.900%** (0.900–0.900) | **2.953** (2.920–3.319) | **33.70 MB** (31.86–34.19) | **35.31 MB** (35.14–35.38) | Display counters stop, but **fails** CPU increment gate: +0.172 percentage points over menu-bar median |

Raw summaries and per-run evidence are under `menu-bar-only/`, `quick-panel-cards/`,
`settings-used-then-closed/`, and `settings-used-then-closed-replacement/` beside this file.

The original `settings-used-then-closed/run-3` is deliberately excluded from the summary. Its
signposts show a user-opened Quick Panel at 20:01:14 (`quickPanelUpdate`, disk, process, sensor and fan
work together). The benchmark now ignores status-item clicks. The replacement full-duration run has
valid end state and zero preview/process/sensor/fan counts; the invalid raw run remains for audit.

## Counter and stack findings

- All formal menu-bar runs retained 300 scheduling/snapshot generations at the two-second interval.
  Snapshot commit maximum was 0.277 ms. Menu-bar `sample` found the main thread waiting for events in
  8,600 of 8,619 samples; active stacks were primarily status-item image drawing.
- All valid Quick Panel runs retained 300 root updates and 300 snapshot generations. Snapshot commit
  maximum was 0.089 ms, but disk sampler boundaries reached 40.689 ms and `/bin/ps` process scans
  reached 125.660 ms. The stack sample contains sustained AppKit DisplayLink/SwiftUI activity plus
  sensor and process work. Boundary duration does not itself prove a frame hitch; Instruments remains
  required for that causality.
- Valid settings-closed runs recorded zero `settingsPreviewRender`, `processScan`, `samplerSensors`,
  and `samplerFans` calls. Resource use nevertheless did not return to the menu-bar-only baseline.

The prior 8.55% diagnostic observation and the formal 5.933% Quick Panel median are not identical
uptime conditions, but the measured reduction is only about 30.6%, not the provisional 60% target.
The high-cost state is therefore confirmed, not resolved.

## Short coverage (non-gating smoke)

These runs use two-second warm-up and 10–22 measured seconds. They validate automation, surface
state, and probe coverage; they are not substitutes for formal traces.

| Scenario | Average CPU | p95 CPU | Finding |
|---|---:|---:|---|
| Quick Panel gauges | 8.970% | 24.200% | Valid visible state; requires formal follow-up |
| Settings overview | 0.934% | 2.100% | Visible state validated |
| Settings menu bar | 6.987% | 9.500% | Preview renderer active; requires formal follow-up |
| Settings popover | 14.678% | 24.200% | Live-root preview active; requires formal follow-up |
| Settings sampling | 0.391% | 0.800% | Visible state validated |
| Settings sensors | 0.410% | 0.800% | Visible state validated |
| Settings alerts | 0.397% | 0.800% | Visible state validated |
| Settings advanced | 0.386% | 0.800% | Visible state validated |

The lifecycle driver completed exactly 100 Quick Panel + settings cycles and ended with both windows
closed. Pre-cycle footprint was 17.08 MB, final footprint 54.92 MB, growth **37.84 MB**, and peak
85.42 MB. This **fails** the +5 MB gate. Raw evidence is under
`coverage-smoke/panel-settings-100-cycles/`.

## Instruments evidence

- `xctrace-time-profiler/run-1/Time-Profiler.trace` is a valid optimized Quick Panel cards recording:
  600.859 seconds, `Time limit reached`, with 35,351 exported time-sample rows in
  `time-samples.xml.gz`. Its same-run process summary was 5.815% average CPU, 12.7% p95,
  16.055 wakeups/s, 54.28 MB starting footprint, 54.95 MB final footprint, and 61.17 MB peak.
- SwiftUI failed before recording in both attach and direct-launch forms with
  `Failed starting ktrace session`. Developer Mode is currently disabled; that fact is recorded as
  system state, not asserted as the cause.
- The Xcode 26 template name is `Animation Hitches`. A formal 600-second recording reached the time
  limit, but saving expanded to approximately 43 GB of logical trace data, filled the APFS container,
  and aborted. The invalid artifact was removed. Repeating it with less than 1 GB free would risk the
  machine rather than produce trustworthy evidence.

## Gates not closed on this machine

1. Two additional Time Profiler repetitions plus valid SwiftUI and Animation Hitches recordings.
   SwiftUI currently cannot start ktrace; Animation Hitches needs substantially more free storage.
2. Ten-minute/three-repeat formal recordings for gauges and every settings destination; only short
   coverage exists for those views.
3. Lock, screen sleep, system sleep/wake manual matrix.
4. Manual fan, saved curve, and dependency-injected thermal-safety matrix. No hardware was heated or
   fan ownership changed merely to manufacture evidence.

WP0 cannot be marked Complete while these direct-evidence requirements remain open. WP1 remains
Pending and WP0 remains the sole Next package.
