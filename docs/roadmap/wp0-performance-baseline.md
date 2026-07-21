# WP0 reproducible performance baseline

## Controlled environment

- Build: optimized native Release app from the current checkout.
- Fixture: [`Fixtures/Performance/baseline-all-modules-2s.plist`](../../Fixtures/Performance/baseline-all-modules-2s.plist).
- Fixture semantics: two-second refresh; CPU/GPU/memory menu metrics; every Quick Panel module
  enabled; alerts and fan curve disabled; English/system appearance.
- Warm-up: 120 seconds.
- Measurement: 600 seconds.
- Repetitions: three per gating scenario.
- Isolation: no other `N1KOState` process. The runner refuses a concurrent copy unless explicitly
  overridden for a non-gating smoke run.
- User defaults: exported before the first run and restored on every exit path.

The runner records cumulative CPU time, one-second CPU samples, task wakeups, resident/physical
footprint, peak footprint, `vmmap`, a stack `sample`, signpost events, and the in-process counters.
When full Xcode is available it additionally records the selected xctrace template.

### Measurement integrity

- `proc_pid_rusage` reports user/system CPU in Mach absolute-time units. The native helper converts
  both fields through `mach_timebase_info` before emitting nanoseconds; this matters on Apple
  Silicon, where the units are not one nanosecond per tick.
- A two-second CPU-saturated calibration process on the measurement machine produced a converted
  CPU delta of 2.002 seconds (the expected scheduler-scale result). The unconverted value was about
  41.7 times too small and was rejected before formal evidence collection.
- Average and p95 CPU are expressed as percentage of one logical CPU, matching macOS `top`; they
  are not divided by the machine's logical-core count.
- The runner's defaults backup/restore path is checked by canonical plist comparison in the smoke
  run. Cleanup waits for the benchmark process to exit before importing the backup, so late app
  shutdown writes cannot overwrite the restored values. Benchmark fixture values do not remain in
  the user's defaults after exit.
- The runner records and validates expected end-state visibility. Quick Panel runs additionally
  require at least one root update per four measured seconds, settings/menu-bar runs ignore status
  item clicks, and the lifecycle scenario must report exactly 100 completed cycles.

## Automated scenarios

| Scenario | Runner name | Controlled state |
|---|---|---|
| Menu-bar-only background | `menu-bar-only` | No N1KO window visible |
| Cards, all modules | `quick-panel-cards` | Quick Panel open in cards mode |
| Gauges, all modules | `quick-panel-gauges` | Quick Panel open in gauges mode |
| Each settings destination | `settings-overview`, `settings-menu-bar`, `settings-popover`, `settings-sampling`, `settings-sensors`, `settings-alerts`, `settings-advanced` | One stable destination visible |
| Settings used then closed | `settings-used-then-closed` | Overview shown for five seconds during warm-up, then closed before counters reset |
| Lifecycle stress | `panel-settings-100-cycles` | 100 Quick Panel and 100 settings open/close cycles after warm-up |

Formal example:

```bash
WARMUP_SECONDS=120 MEASUREMENT_SECONDS=600 REPETITIONS=3 \
  scripts/run_performance_baseline.sh menu-bar-only
```

For Instruments evidence, run separate recordings so templates do not contend with each other:

```bash
REQUIRE_XCTRACE=1 XCTRACE_TEMPLATE="Time Profiler" scripts/run_performance_baseline.sh menu-bar-only
REQUIRE_XCTRACE=1 XCTRACE_TEMPLATE="SwiftUI" scripts/run_performance_baseline.sh quick-panel-cards
REQUIRE_XCTRACE=1 XCTRACE_TEMPLATE="Animation Hitches" scripts/run_performance_baseline.sh quick-panel-cards
```

Template spelling must be confirmed by `xcrun xctrace list templates` on the measurement machine.

## Manual safety/lifecycle scenarios

These scenarios must not be faked through UI automation or by heating hardware deliberately.

1. **Lock/screen sleep/system sleep/wake:** start a trace, lock for two minutes, wake and unlock;
   repeat with display sleep and system sleep. Verify immediate post-wake refresh, reset rate
   baselines, fan safety continuity, and counter/task return to steady state.
2. **Manual fan:** with the helper already authorized, select one fan, record automatic RPM, set a
   conservative in-range manual target for 60 seconds, then reset to automatic. Verify only the
   selected fan was owned and the final SMC state is automatic.
3. **Curve:** enable the existing saved curve without editing its points, observe two curve
   evaluation windows, then disable it. Verify hysteresis/minimum interval and automatic reset.
4. **Thermal alert/safety:** use existing focused tests or a dependency-injected temperature
   fixture; do not generate real thermal stress. Verify the safety override wins over manual/curve
   state and reset returns to automatic control.

## Evidence interpretation

- Average CPU comes from `proc_pid_rusage` user+system time delta divided by measured wall time.
- p95 CPU comes from sorted one-second `top` samples.
- Wakeups are package-idle plus interrupt wakeup deltas per second.
- SwiftUI update counts use `quickPanelUpdate` and `settingsPreviewRender`; platform render and
  cause/effect/hitch analysis still requires the SwiftUI and Animation Hitches Instruments templates.
- Main-thread hotspots use Time Profiler/xctrace when available; `sample` is a non-gating fallback.
- Signpost counter averages are boundary timings, not substitutes for CPU or frame-time traces.

## Current tool constraint

The machine has Xcode 26.3 and a working `xctrace`. One valid 600.859-second Time Profiler recording
completed at the time limit and exported 35,351 time-sample rows. The SwiftUI template fails before
recording for both direct launch and attach with `Failed starting ktrace session`; Developer Mode is
currently disabled, but this observation does not prove causality. A formal Animation Hitches run
reached its time limit, then expanded to approximately 43 GB of logical trace data while saving,
filled the APFS container, and aborted. The invalid trace was removed. With less than 1 GB currently
free, repeating that write is unsafe until storage is made available. WP0 therefore cannot claim the
remaining SwiftUI/Animation Hitches or three-repetition Instruments gates.

## Results

Formal results and gate evaluation: [2026-07-15 measurement results](evidence/wp0/2026-07-15/results.md).
The roadmap status summary is recorded in `04-delivery-plan.md`. Raw per-run artifacts live under
`docs/roadmap/evidence/wp0/` and include `summary.tsv`, `performance-counters.json`, `signposts.txt`,
`time-profile.sample.txt`, `vmmap-summary.txt`, rusage snapshots, and the valid Time Profiler trace.
