# WP3 Agent Core results — 2026-07-16

Checkout: `09cde29c24d20f8b97f0fd2995a686fac0cb3ab7` plus retained uncommitted
WP0/WP1/WP2 work and this WP3 implementation. No commit, push, tag, release, signing identity,
notarization, or publication was performed.

## Delivered boundary

- SwiftPM now contains an isolated `N1KOAgentCore` target. It depends on Foundation, Security,
  Darwin, Dispatch, and `os.signpost`; it has no presentation, settings, updater, monitor, or
  concrete app-server dependency.
- N1KO-owned `AgentSessionCoordinator` is the sole Agent lifecycle owner. It owns ingress sources,
  the lifecycle/association/persistence store, response routes, task/subprocess shutdown, immutable
  `AgentSnapshot` publication, and Agent-only sleep/session energy policy.
- Claude hook and bounded transcript parsers plus Codex rollout and JSON-RPC app-server parsers
  normalize into one event model. Codex rollout watching uses vnode events, not polling. App-server
  input is injected through `CodexAppServerTransport`.
- The store merges provider/session identity, persists cumulative usage and lifecycle, restores
  sessions without persisting response capabilities, completes/interrupts/fails/archives sessions,
  and exposes approval/question/completion/failure attention.
- Approve/deny/answer routes require matching provider, canonical session, request, connection owner,
  and an unpredictable process-local capability. Socket ingress additionally requires the current
  peer UID and a constant-time per-install secret match.
- N1KO runtime paths use a short per-user directory under `$TMPDIR`; parent and Application Support
  directories are 0700, the socket and secret are 0600. Diagnostic JSON/text removes secrets,
  tokens, prompts/answers, tool inputs, arguments, and the home path.
- AppDelegate starts and stops only this coordinator and forwards public workspace sleep/wake,
  screen, and active-session notifications. MonitorHub scheduling and fan/thermal safety ownership
  were not changed. No Agent UI, Island, top-edge panel, or fullscreen window was added.

## Lifecycle and security evidence

The final Agent suite has 21 focused tests covering:

- Claude hook + transcript and Codex rollout + app-server parsing;
- receive, merge, association, cumulative usage, restore, completion, interruption, archive,
  and attention state;
- pending approval, question, resolution, external-only rollout attention, and immutable snapshots;
- approve/deny/answer success plus wrong request, owner, capability, provider-channel, and closed
  route rejection;
- real Unix socket mode, current-peer UID acceptance, incorrect UID predicate, valid install secret,
  and incorrect install-secret rejection;
- diagnostics redaction and persistence that excludes response capabilities;
- app-server transport ingestion/stop, event-driven rollout restore, 1,000-event lifecycle
  projection bound, and first-line + 1 MiB tail reading for large rollouts;
- sleep/session lifecycle policy and shutdown of socket, watcher, transport, cancellable task,
  subprocess, and response channel.

Graceful automated app exits recorded:

```text
AgentCore shutdown socket=1 watchers=1 transports=0 tasks=0 subprocesses=0 remaining=0
```

The same zero-remaining result was recorded for every enabled benchmark repetition.

## Agent enabled-idle measurement

Command shape (same optimized native app and performance fixture for both states):

```bash
N1KO_AGENT_ENABLED=<0|1> WARMUP_SECONDS=20 MEASUREMENT_SECONDS=60 \
  REPETITIONS=3 SAMPLE_SECONDS=5 SKIP_BUILD=1 XCTRACE_DEVELOPER_DIR=/nonexistent \
  OUTPUT_ROOT=docs/roadmap/evidence/wp3/2026-07-16/<state> \
  scripts/run_performance_baseline.sh agent-core-idle
```

The runner measures 58 seconds after its stack-sample allowance, validates that Quick Panel and
Settings remain hidden, resets Agent counters at the measurement boundary, and restores user
defaults after every group.

| State | Average CPU median (runs) | p95 median | Wakeups/s median | Final footprint median | Growth median |
|---|---:|---:|---:|---:|---:|
| Agent disabled | 0.244% (0.228, 0.244, 0.247) | 0.900% | 2.362 | 15.77 MB | +0.72 MB |
| Agent enabled, post-projection | 0.274% (0.200, 0.277, 0.274) | 0.800% | 2.328 | 60.31 MB | +0.56 MB |
| Enabled minus disabled median | **+0.030 percentage points** | -0.100 pp | -0.034 | +44.54 MB | -0.16 MB |

All three enabled measurement windows had zero Agent ingress and 125 restored sessions. The CPU
delta is small relative to the same-build monitor-only state, and wakeups did not increase.

### Restore-path failure found and fixed

The retained `agent-enabled-idle-invalid-pre-coalescing` group is intentionally invalid: the first
implementation replayed approximately 12,000 historical JSONL events for 125 sessions and wrote a
snapshot after every event. Runs two and three measured 10.289% and 10.875% average CPU while that
startup queue was still draining. This was not relabeled as idle or discarded.

The fix projects each rollout to at most identity, latest cumulative usage, and latest semantic
state; equal/older persisted events are idempotent; file reading keeps the complete session-meta
line and at most the last 1 MiB instead of materializing the conversation. A final-code clean-state
diagnostic restored 200 sessions and measured:

| Average CPU | p95 | Wakeups/s | Start -> final footprint | Peak | Measured ingress |
|---:|---:|---:|---:|---:|---:|
| 0.308% | 0.900% | 2.897 | 24.19 -> 24.30 MB | 25.30 MB | 0 |

That final-code run is +0.064 percentage points over the disabled three-run median. Despite restoring
more sessions, bounded reading reduced the first-run peak from 225.30 MB to 25.30 MB and final
footprint from 60.31 MB to 24.30 MB. The remaining approximately +8.5 MB versus disabled reflects
the socket/watcher, 200 immutable session states, persistence, and parser/runtime caches.

`N1KOAgentCore` contains no `CVDisplayLink`, `CADisplayLink`, or display-link setup. Five-second stack
samples contain only the existing AppKit `CATransaction ... NS_setFlushesWithDisplayLink` callback in
both disabled and enabled runs; no Agent-owned continuous render/update loop appears. Quick Panel
and Settings counters remain absent. The gate is therefore based on the core source boundary,
same-build control, zero ingress, CPU/wakeup result, and stack comparison—not on claiming AppKit has
no display machinery at all.

## Build, compatibility, regression, and legal verification

- `swift test`: **69 tests, 0 failures, 2 expected skips**. The skips are the unmounted installer
  DMG fixture and the opt-in sustained process comparison. Agent Core contributes 21 passing tests.
- `swift build`: pass.
- Full Agent module typecheck with Swift 5 language mode and
  `-target arm64-apple-macosx12.0`: pass; minimum macOS remains 12.
- `./build_app.sh --native --smoke`: pass; Release smoke idle sample **0.0%**.
- Native app assembly contains the readable Agent notice and exact 201-line Apache license;
  `codesign --verify --deep --strict` passes for the ad-hoc local bundle.
- `plutil -lint Resources/Info.plist Localization/*/Localizable.strings`: pass.
- `bash -n build_app.sh scripts/run_performance_baseline.sh`: pass.
- `git diff --check`: pass.
- Core scans for AppKit/SwiftUI, upstream app shell/settings/updater/analytics, `CGS*`/`SLS*`/
  SkyLight, and display-link APIs: clean. Legal modification comments are the only upstream-name
  source matches.
- Full file-level migration/license result: [migration and license checklist](migration-license-checklist.md).

## Remaining WP3 caveats handed forward

- The socket and app-server response protocol is proven locally, but WP5 still owns managed hook
  installation/takeover, coexistence, rollback, remote/SSH, tmux/focus, and all non-Claude/Codex
  providers. WP3 intentionally does not edit any third-party config.
- `CodexAppServerTransport` is a protocol boundary; the production default receives Codex through
  rollout events and the authenticated hook socket. A concrete live app-server connection may be
  supplied in the later integration-parity package without changing session ownership.
- A 200-session restore retains about 8.5 MB more final footprint than Agent-disabled control. This
  is measured and bounded, not a leak claim; longer active-session/large-history soak remains WP6.
- AppKit transaction-flush frames exist in both control and enabled samples. The Agent target owns no
  display link, but WP4 must still prove that its future Island surfaces suspend rendering when hidden.
- No WP4 fullscreen/Island acceptance item was exercised or implemented here.
