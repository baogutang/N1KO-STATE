# Retained pre-final monitoring-only soak start/lifecycle check

- Runner directory: `soaks/monitoring-only/20260716T110550Z`
- Runner PID at check: 35090; isolated N1KOState PID: 35141.
- Warm-up completed and the formal 86,400-second measurement began at
  `2026-07-16T11:07:55Z` (`ready` exists).
- Evidence directory and both TSV streams are private: directory 0700, sample files 0600.
- First complete 61-second interval: 0.218711% average CPU, 0.735071 mW average process energy,
  1.852459 wakeups/s, -0.171875 MB physical-footprint delta, and zero thread/FD/socket growth.
- Internal samples remained stable: history advanced from 4 to 6 samples per series; Agent is
  disabled with zero sockets/watchers/transports/tasks/subprocesses/routes; two snapshot observers
  remained constant; surface monitors/retries and lifecycle-event counters remained zero.

This start check proves only that the corrected run entered measurement with the expected schema
and stable initial interval. The run later crossed two real sleep/wake cycles, then was intentionally
interrupted when the live audit identified a history-file permission hardening gap. It remains valid
lifecycle/interruption evidence, but it is not final-candidate or 24-hour performance evidence.
