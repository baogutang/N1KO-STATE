# WP0 closeout evidence — 2026-07-16

Checkout: `09cde29c24d20f8b97f0fd2995a686fac0cb3ab7` plus the uncommitted WP0 implementation.

## Added formal evidence

| Scenario | Repetitions | Average CPU | p95 CPU | Wakeups/s | Final footprint |
|---|---:|---:|---:|---:|---:|
| Quick Panel gauges | 3 | 9.842% median | 20.900% median | 42.398 median | 35.69 MB median |
| Settings Overview | 3 | 0.934% median | 2.000% median | 4.234 median | 37.59 MB median |
| Settings Menu Bar | 2 valid; third stopped | 7.107%, 8.226% | 9.700%, 9.900% | 88.697, 91.201 | 42.70, 42.84 MB |

All completed runs reported a valid final scenario state. The interrupted Settings Menu Bar third
run was deleted and is not counted.

## Time Profiler completion

Three optimized Quick Panel cards traces now exist:

| Trace | Duration | End reason | Time-sample rows |
|---|---:|---|---:|
| 2026-07-15 run 1 | 600.858844 s | Time limit reached | 35,351 |
| 2026-07-16 run 1 | 602.875915 s | Time limit reached | 41,716 |
| 2026-07-16 run 2 | 600.881134 s | Time limit reached | 40,763 |

The two 2026-07-16 process summaries measured 6.853% and 6.756% average CPU with 15.3% and 15.1%
p95 while instrumented. These are kept separate from the non-Instruments formal baseline.

## User-directed stop and retained risks

On 2026-07-16 the user explicitly stopped the remaining long-running settings occupancy tests and
directed work to continue to subsequent implementation. No further repetitions are inferred or
fabricated. SwiftUI still fails to start its ktrace session, the formal Animation Hitches save
previously exhausted available storage, and the manual sleep/fan/thermal matrix remains unexecuted.
These are retained risks for the affected implementation paths and release hardening.
