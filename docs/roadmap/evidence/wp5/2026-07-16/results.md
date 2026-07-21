# WP5 Full integration parity and migration results — 2026-07-16

Checkout: `09cde29c24d20f8b97f0fd2995a686fac0cb3ab7` plus retained uncommitted
WP0–WP4 work and this WP5 implementation. Compatibility input was rechecked at the clean pinned
upstream commit `da130d679e830894240e926184d29751dfd2def1`. No commit, push, tag, release,
Developer ID signing, notarization, publication, or user hook/defaults import was performed.

## Delivered integration boundary

- `N1KOAgentCore` now owns a 19-profile provider/client registry with 17 explicitly managed
  integrations and two runtime-only profiles. It covers Claude, Codex, Gemini, Qwen, Kimi, Hermes,
  Pi, OpenCode, OpenClaw, Qoder/Qoder CLI/QoderWork, CodeBuddy/CodeBuddy CLI, WorkBuddy, Cursor,
  GitHub Copilot, Trae, and JetBrains Agent/plugin boundaries. The full audited mapping and evidence
  boundary is in the [provider parity matrix](provider-parity-matrix.md).
- `N1KOAgentBridge` is a separately signed N1KO executable. It caps stdin, loads the private
  per-install secret, connects only to the per-user private Unix socket, sends provider/profile
  metadata without treating it as authentication, and requires the authenticated server reply.
- Provider-aware parsing retains navigation context and exact response ownership. Wrong peer UID,
  secret, provider channel, request owner, capability, or expired response channel fails closed.
- `AgentSessionCoordinator` remains the only store/session/runtime/response owner. Multiple read-only
  snapshot observers allow the existing UI and the single updater deferral gate to observe one
  truth without creating a second store.

## Hook takeover, coexistence, and rollback

- Managed installation writes exact per-profile N1KO markers and preserves unrelated JSON/TOML
  keys and plugin files. Each touched file gets an exact 0600 backup and before/staged/final hash.
- Installation stages the new entry beside any recognized legacy entry, executes the actual bridge
  probe with a three-second bound, rechecks file hashes, and only then removes exact legacy
  references. Probe failure restores the exact original bytes; a concurrent edit is never
  overwritten.
- Same-schema installation is a no-write idempotent result. Upgrade is recorded, downgrade is
  rejected, and explicit removal/rollback append ledger entries. User replacement of a plugin or
  post-install configuration prevents destructive removal/rollback.
- A 0600 per-user ownership lease blocks takeover while the exact legacy bundle or another live
  N1KO owner is running, preventing reinstall loops. No hook is installed automatically; Agent
  Center requires a confirmation for install, removal, takeover, or optional legacy import.

## Preference and data migration

- The one N1KO settings migrator runs before `AppSettings` construction. Schema 2 writes an exact
  defaults plist backup before mutation, imports only absent allowlisted keys from the previous
  N1KO domain, removes obsolete presentation keys, and appends a private idempotent ledger.
- Optional legacy Agent import is read-only and confirmation-gated. It may import associations,
  preferred integration profiles, and aggregate usage/cache without overwriting newer N1KO
  associations. It never imports secrets, credentials, hook ownership, or transient window state.
- The exact legal, identity, migration, retention, and bundled-license disposition is in the
  [migration/license checklist](migration-license-checklist.md). During final review the previously
  missing bundled Sparkle and SMCKit license copies were added and the inaccurate notice reference
  was corrected.

## Focus, tmux, remote, optional surface, and updates

- Terminal/IDE focus uses public `NSWorkspace` activation/open behavior. A supplied tmux target is
  strict-character validated and invoked through `/usr/bin/tmux` arguments without a shell.
- Remote SSH is an optional, default-off protocol boundary: typed Codable endpoint, mandatory
  SHA256 host fingerprint, strict host checking, batch mode, non-shell argument validation, and no
  implicit host contact. No remote host was available or contacted in WP5, so live remote bootstrap,
  transport recovery, and host compatibility remain release-hardening evidence, not claimed passes.
- Provider companions are default-off SF Symbols. No third-party mascot, logo, font, sound, or
  image asset is bundled.
- The existing single `UpdateController` defers update relaunch while any Agent session is active
  and invokes the pending install exactly once when sessions become idle. No update was published.

## Scoped performance result

This is a short WP5 `agent-core-idle` integration gate, not a repeat of the discontinued Menu Bar
settings occupancy matrix. It used one native isolated run, 15-second warm-up, 35-second requested
measurement, and an Xcode Time Profiler trace. The measured rusage window is 33 seconds after the
stack-sample allowance; the fixture restores 200 sessions with Agent Core enabled.

| Average CPU | p95 CPU | Wakeups/s | Start -> final footprint | Growth | Peak |
|---:|---:|---:|---:|---:|---:|
| **0.195%** | **0.800%** | **2.121** | 21.20 -> 22.31 MB | **+1.11 MB** | 23.89 MB |

At the measurement boundary: ingress=0, Agent surface visible=false, snapshot compositions=0,
global monitors=0, retry tasks=0, and scenario-state validation=true. Artifacts, Time Profiler
trace, rusage, stack sample, signposts, and counters are retained under
[`performance/agent-core-idle/`](performance/agent-core-idle/).

## Validation

- `swift test`: **99 tests, 0 failures, 3 expected opt-in/environment skips**. The skipped checks
  are unmounted installer-DMG filtering, the sustained libproc comparison, and the live WP4
  pseudo-fullscreen latency gate; their prior-package evidence remains retained.
- `swift build`: pass.
- `plutil -lint Resources/Info.plist Localization/*/Localizable.strings`: pass;
  `scripts/sync_localization.sh`: all English/Simplified/Traditional key sets match.
- `bash -n build_app.sh scripts/*.sh` and `git diff --check`: pass.
- `./build_app.sh --native --smoke`: Release assembly and smoke pass; final smoke idle sample was
  0.5% CPU.
- Strict deep ad-hoc signature verification: pass. Main identifier is `com.n1ko.state.monitor`;
  bridge identifier is `com.n1ko.state.monitor.agent-bridge`.
- `otool -l`: both main executable and Agent bridge report `minos 12.0`.
- Source and linked-symbol private-API scan: clean. Identity allowlist gate: pass. One `@main`, one
  `AppDelegate`, one `AppSettings`, one `UpdateController`, and one `PresentationCoordinator` remain.
- Bundle inspection: readable NOTICE plus Apache, Sparkle, and SMCKit license files are copied into
  `Contents/Resources/ThirdPartyNotices/`.

## Evidence boundary and remaining release risks

WP5 has direct automated fixture/config-shape coverage for every audited profile, a real local
bridge/socket probe, current-machine native packaging, and a scoped native idle trace. It does not
claim live execution inside all 19 third-party clients, a real SSH host, a different user account,
macOS 12 hardware, Intel hardware, mixed/notched display hardware, or a 24-hour soak. Those are
explicit WP6 matrices. The legacy identity allowlist must be removed at settings schema 4 after the
two-version rollback window.

Every WP5 deliverable and gate now has direct evidence at the available safe boundary. WP6 is the
sole dependency-satisfied **Next** work package.
