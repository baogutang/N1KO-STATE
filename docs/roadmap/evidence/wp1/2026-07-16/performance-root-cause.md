# WP1 Quick Panel performance root-cause disposition

This disposition uses the valid optimized WP0 Quick Panel cards run and its ten-second stack sample;
it does not repeat the user-stopped Menu Bar settings occupancy test.

## Evidence

The formal cards scenario ran for 600 seconds after a 120-second warm-up and measured 5.933% median
average CPU across three repetitions. In run 1, the retained counters recorded 300 coherent display
updates, matching the configured two-second cadence.

Instrumented boundary durations in that run were approximately:

| Boundary | Total elapsed time inside boundary |
|---|---:|
| Temperature sensor reads on the SMC/IOHID worker | 8.987 s |
| Process scans | 1.351 s |
| Menu-bar rendering | 0.270 s |
| Disk sampling | 0.202 s |
| Fan reads | 0.281 s |
| CPU, GPU, memory and network samplers combined | 0.207 s |
| Scheduling and snapshot commits combined | 0.027 s |

These durations are signpost wall time and can overlap across queues, so they are not subtracted from
the process's approximately 35.6 CPU-seconds. They do establish frequency and placement: the
longest sampler boundary is temperature acquisition on its dedicated worker, while snapshot commits
and menu rendering are small and bounded.

The retained stack sample independently locates that remainder in the visible SwiftUI/AppKit render
tree. Of 7,663 main-thread samples, 7,302 were blocked waiting for events. The active paths are
dominated by `CA::Transaction::commit`, `NSDisplayCycleFlush`, `NSHostingView.layout`,
`ViewRendererHost.render`, `ViewGraph.updateOutputs`, and AttributeGraph/layout sizing. The same
sample shows repeated hosting-view constraint and content-size evaluation for the visible popover.

## Disposition

WP1 moves CPU/memory/network/GPU/disk acquisition away from the main actor and prevents hidden
Settings/Quick Panel work after teardown. It does not reduce monitoring cadence, sensor safety, or
visible data publication to make the number pass. The remaining visible Quick Panel CPU is a
presentation-tree/layout/motion problem whose implementation scope is explicitly WP2.

Therefore the original 2.5% visible-surface provisional gate is not used as a WP1 sampler gate. It
remains a product performance target for the WP2 Quick Panel rebuild. This is a scope attribution,
not a relaxation of the final target: WP2 must measure the rebuilt surface against the same
optimized fixture, and WP6 must repeat the release matrix.

Source artifacts:

- `evidence/wp0/2026-07-15/quick-panel-cards/summary.tsv`
- `evidence/wp0/2026-07-15/quick-panel-cards/run-1/performance-counters.json`
- `evidence/wp0/2026-07-15/quick-panel-cards/run-1/time-profile.sample.txt`

## Scoped post-change sanity check

A single optimized cards run after WP1 used the same all-modules/two-second fixture with a
five-second warm-up and a 30-second measurement window. It deliberately used the small
sample/signpost backend, did not run a Menu Bar occupancy scenario, and did not generate xctrace
data on the nearly full volume.

| Metric | Formal WP0 median | Scoped post-WP1 run |
|---|---:|---:|
| Average CPU | 5.933% | 5.285% |
| p95 CPU | 13.100% | 13.900% |
| Wakeups/s | 16.415 | 20.679 |
| Final footprint | 56.74 MB | 45.95 MB |

The short run is diagnostic, not a statistically equivalent replacement for the three 600-second
repetitions. Its mixed result (lower average CPU/footprint but higher p95/wakeups) does not justify
changing sampling semantics. The still-high visible CPU and wakeups reinforce the retained stack
sample's WP2 presentation-tree attribution.
Artifacts are under `evidence/wp1/2026-07-16/post-change-quick-panel-cards/`.
