# WP6 release-hardening results — in progress

WP6 is not complete. The infrastructure and automated gates below are direct evidence; the two
independent 24-hour runs and unavailable/manual matrices remain release blockers.

## Implemented hardening

- Added an opt-in release-soak path that samples cumulative CPU, cumulative energy/average power,
  wakeups, resident/physical/peak
  memory, threads, file descriptors, sockets, history counts, Agent sockets/watchers/transports,
  registered/active tasks and subprocesses, pending response routes, snapshot observers, Agent
  sessions, surface monitors/retries, and lifecycle notifications.
- Soaks redirect defaults-sensitive setup, Agent runtime/support, Codex rollouts, and history to
  isolated private locations. Interrupting the runner stops the app, restores defaults, removes the
  runtime secret, and retains partial evidence with an explicit interrupted status.
- The analyzer computes full-window CPU/wakeup rates, p95 interval CPU, physical-footprint growth
  and regression slope, and all resource deltas. Runs shorter than 86,400 seconds are labelled
  `calibration`; the 24-hour slope gate is deliberately not applied to short windows.
- Agent-enabled soaks seed exactly 200 synthetic sessions before measurement, through the real
  separately signed bridge and authenticated 0600 socket, without reading or changing a live client.
- Disk logs and exported logs now share secret, authorization, credential, response owner,
  capability, session ID, URL credential, and home-user redaction. Export work/zip permissions are
  0700/0600, the archive contains a privacy manifest, and settings state that export is local,
  explicit, redacted, never auto-uploaded, and should be reviewed before sharing.
- Removed the two duplicate localization keys per locale while preserving the previously effective
  translations. The final gate rejects all future duplicate keys.

## Calibration results (not release evidence)

| Scenario | Window | Avg CPU | p95 CPU | Wakeups/s | Footprint delta | Thread/FD/socket growth | Agent internal growth |
|---|---:|---:|---:|---:|---:|---:|---:|
| Monitoring only | 18 s measured | 0.180% | 0.432% | 2.111 | +0.125 MB | 0 / 0 / 0 | all zero |
| Agent enabled, 200 fixtures | 18 s measured | 0.103% | 0.182% | 2.056 | -0.219 MB | -6 / 0 / 0 | all zero |

The monitoring calibration originally reached the summarizer with complete raw evidence but hit a
BSD awk reserved-word incompatibility. The analyzer was fixed and the retained samples recomputed;
both final calibration summaries are `CALIBRATION_PASS`. Short-window footprint slopes are recorded
but are not stability evidence and do not satisfy the 24-hour gate.

A follow-up 9-second monitoring calibration verified the cumulative v6 energy counter and analyzer:
0.149% average CPU, 4.893 mW average power, 2.667 wakeups/s, and no thread/FD/socket growth. It is
also calibration only. The first attempted long-run launch was interrupted before measurement when
the missing energy column was noticed; partial evidence was retained. The first energy-capable
long-run candidate started at `2026-07-16T11:05:50Z` under
`soaks/monitoring-only/20260716T110550Z`.
Warm-up completed at `11:07:55Z`; the first full 61-second interval recorded 0.219% CPU,
0.735 mW process energy, 1.852 wakeups/s, -0.172 MB footprint, zero thread/FD/socket growth, stable
internal resource counts, and advancing isolated history. This is a start check, not a 24-hour
result; see [soak start check](soak-start-check.md).

The retained `11:05:50Z` run subsequently crossed two real current-machine sleep/wake cycles. System power logs,
N1KO lifecycle logs, wall-clock/monotonic deltas, and internal counters agree: roughly 1084 seconds
were asleep, the process survived, history resumed without sleep backfill, system sleep/wake
balanced 2/2, and all disabled-Agent resources stayed at zero. This closes real monitoring-only
sleep/wake evidence for the observed cycles, but not explicit lock/unlock or fast-user switching.
See [lifecycle matrix in progress](lifecycle-matrix-in-progress.md).

A live `lsof`/permission audit then found the isolated `history.json` at 0644. Its parent evidence
directory was already 0700, so no other user could traverse it, but the final product invariant is
now stricter: the N1KO-STATE history directory is enforced to 0700 and both existing and newly
written history files to 0600. A new regression test verifies creation and repair. The run was
interrupted rather than mislabelled as final-candidate evidence. The full suite is now 104 tests,
0 failures, 3 expected skips; native Release smoke and the release gate pass after rebuilding.
The final-candidate monitoring-only run started at `2026-07-16T11:36:37Z` under
`soaks/monitoring-only/20260716T113637Z`; measurement began at `11:38:44Z`. The runner/app remained
alive after warm-up, the first history file was directly verified as 0600, and the first complete
60-second interval recorded 0.332% CPU, approximately 1.365 mW, 2.883 wakeups/s, -0.266 MB
physical-footprint change, advancing history, no FD/socket growth, zero Agent session/runtime
resources, and two stable snapshot observers. This is only a start/continuity check, not 24-hour
performance evidence; see [final-candidate start check](soak-final-candidate-start-check.md).
The run was intentionally interrupted at approximately `11:57:23Z` after 1,093.003 monotonic awake
seconds when the user reported that the Agent Island was unavailable. The root cause was the soak
architecture rather than a shipping-window failure: the monitoring-only process explicitly
disabled Agent Core and occupied the sole allowed N1KO process slot, replacing the user's normal
current-checkout UI. Keeping that arrangement for 24–48 hours is an unacceptable user-visible test
side effect. The conditional Agent-enabled handoff was cancelled and no Agent-enabled run started.

The retained partial window averaged 0.363% CPU, 2.039 mW, and 3.059 wakeups/s, with +0.750 MB
physical-footprint change, threads 12 to 11, FD 5 to 5, sockets 0 to 0, history counts 4 to 39,
stable internal resource ownership, and 0600 history. These are partial diagnostic values only.
The normal current-checkout build was restored with Agent behavior/presentation enabled and the
active Codex session recognized. Before restarting either release soak, the harness must isolate
its defaults/runtime without displacing, disabling, or altering the user's visible N1KO instance.

## Automated verification so far

- `swift test`: 104 tests, 0 failures, 3 expected environment-gated skips.
- Native optimized build: success, arm64 app assembled; no installer/DMG/release was produced.
- `run_wp6_release_gate.sh`: three localizations parse with unique keys; legal files and bundled
  copies exist; modified-file markers, N1KO identity/update-feed allowlist, one-owner invariants, public
  CGS/SLS/SkyLight boundary, app/bridge `minos 12.0`, strict ad-hoc signatures, and diff hygiene pass.
- `proc_metrics.c`: compiles with `-Wall -Wextra -Werror` and returns thread/FD/socket counts on the
  current process.
- The configured app and updater both use the N1KO appcast at
  `https://raw.githubusercontent.com/baogutang/N1KO-STATE/main/appcast.xml`. A read-only live fetch
  returned N1KO-STATE 1.0.17 with minimum system 12.0 on 2026-07-16. No feed was changed or uploaded.

## Still blocking completion

- Monitoring-only 24-hour soak and independent Agent-enabled 24-hour soak.
- Real sleep/wake, lock/unlock, fast-user-switch, network loss/recovery, and permission denial then
  authorization transitions during the long-run evidence window.
- Manual VoiceOver/keyboard traversal on the release build.
- A live third-party client hook matrix and real remote host, if the user elects to authorize them.
- Physical notched/mixed-display/separate-Spaces hardware and a different-user socket attempt are
  unavailable on this machine. Synthetic/unit evidence cannot be relabelled as physical evidence.
