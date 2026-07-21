# WP6 lifecycle matrix — in progress

This file distinguishes current-machine events from automated policy tests. It does not claim
lock/unlock, fast-user-switch, network-disconnect, or Agent-enabled lifecycle completion yet.

## Real current-machine events during monitoring-only soak

Source: `pmset -g log`, redacted N1KO launch log, and the private count-only soak TSVs.

| Event | System power evidence | N1KO evidence | Result so far |
|---|---|---|---|
| Sleep 1 | 2026-07-16 19:10:45 +08, Idle Sleep, 1017 s | `system-sleep` suspended at 11:10:40Z | Process stayed alive; no Agent/presentation resources appeared |
| Wake 1 | 19:27:42 +08, Deep Idle wake | `system-wake` entered reconciliation at 11:27:42Z | Display UUID temporarily changed during enumeration, then returned to the configured physical display; desktop classification recovered |
| Screen sleep/wake | screen sleep at 11:28:14Z, wake at 11:30:31Z in app log | surface moved to suspended then entering/desktop | No fullscreen-auxiliary path or stale retry/global monitor was retained |
| Sleep 2 | 19:29:19 +08, Idle Sleep, 72 s | count-only stream reached two system-sleep events | Matched by two wake events; process and runner remained alive |
| Wake 2 | 19:30:31 +08, Deep Idle wake | count-only stream reached two system-wake events | Sampling and history resumed without fabricated backfill |

Across the first 1388.115 wall-clock seconds, `DispatchTime` advanced 304.001 seconds, implying
1084.114 seconds asleep. This aligns within notification/sampling boundaries with the two `pmset`
sleep durations (1017 + 72 seconds). The internal history counts advanced from 4 to 14 per series;
they did not insert one sample for every sleeping wall-clock interval. That preserves the existing
30-second record-on-live-sample semantics.

At the same checkpoint:

- wall-clock average: 0.057% CPU, 0.357 mW process energy, 0.459 wakeups/s;
- awake-normalized conservative interim average: about 0.31% CPU, 1.98 mW, 2.54 wakeups/s;
- physical footprint: +1.80 MB from the first sample;
- file descriptors and sockets: no growth;
- Agent sockets/watchers/transports/tasks/subprocesses/routes and surface monitors/retries: all zero;
- system sleep/wake: 2/2; screen sleep/wake: 1/2 (an extra wake notification is allowed during
  initial display reconciliation).

These are partial values only. Memory/thread conclusions come from the complete 24-hour slope and
endpoints, not from this wake-heavy early window.

## Automated coverage retained

- Workspace sleep/wake notifications drive the monitoring lifecycle policy.
- Safety sampling continues while presentation is suspended.
- Wake recovery resets rate deltas and commits a coherent full generation within two seconds.
- Concurrent wake requests coalesce without dropping completion.
- Fan-control tests retain automatic reset and thermal-threshold cancellation behavior.
- Agent lifecycle suspends watchers/transports and cancels registered work without owning monitor
  sampling; shutdown closes all owned resources.

## Still missing real evidence

- explicit screen lock/unlock rather than display sleep/wake;
- fast user switching;
- deliberate network loss and recovery;
- active Agent session across sleep/wake and completion;
- update-install deferral across a real lifecycle event;
- permission denial followed by later authorization.
