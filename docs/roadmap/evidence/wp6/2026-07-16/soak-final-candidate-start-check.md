# Interrupted final-candidate monitoring-only soak start check

- Runner directory: `soaks/monitoring-only/20260716T113637Z`
- Runner start: `2026-07-16T11:36:43Z`
- Measurement start: `2026-07-16T11:38:44Z`
- Mode: `monitoring-only`
- Checkout: `09cde29c24d20f8b97f0fd2995a686fac0cb3ab7` on `main`
- Runner/app at the check: alive; `status.txt` was `running`
- Isolation: evidence/support/Agent/Codex directories 0700; `history.json` 0600
- Standard output/error after warm-up: empty

The first complete 60-second interval recorded 0.332% CPU, approximately 1.365 mW average
process power, 2.883 wakeups/s, and -0.266 MB physical-footprint change. Threads settled from 12
to 5 after the initial sample; FD count stayed at 5 and socket count at 0. CPU, memory, network-down,
and network-up history series each advanced from 4 to 6 samples.

Agent session, socket, watcher, transport, task, subprocess, and pending-route counts all stayed at
zero. The two Agent snapshot observers remained stable at two; surface monitor/retry counts and all
lifecycle-event counters remained zero during this interval.

This is direct start/privacy/continuity evidence only. It is not a performance-budget result and
does not satisfy the 24-hour gate. The runner measures 86,400 monotonic awake seconds, so the
earliest no-sleep completion point is `2026-07-17T11:38:44Z`; host sleep extends wall-clock
completion. The independent Agent-enabled run must not start until this run completes and its
analyzer returns `RELEASE_PASS`.

## Terminal status

The run was intentionally interrupted at approximately `2026-07-16T11:57:23Z` after 1,093.003
monotonic awake seconds. The isolated monitoring-only process set `N1KO_AGENT_ENABLED=0` and
occupied the sole allowed N1KO application slot, so the user's normal current-checkout Agent Center
and Island were unavailable while the soak ran. Preserving this arrangement for 24–48 hours would
make the evidence collection user-visible and disruptive. The partial samples are retained, but
this run is not a final candidate and cannot satisfy the 24-hour gate.
