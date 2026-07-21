# WP6 environment and evidence boundary

Captured: 2026-07-16 (Asia/Shanghai)

## Current-machine evidence

- Checkout at start of WP6: `09cde29c24d20f8b97f0fd2995a686fac0cb3ab7`, branch `main`, with all
  pre-existing WP0–WP5/user changes preserved.
- Host: Mac mini `Mac16,10`, Apple M4, 10 logical CPUs, 16 GB RAM.
- OS: macOS 15.7.7 (`24G720`). The shipping minimum remains macOS 12.0; this host is not macOS 12.
- Physical display: one attached external notchless Kuycon G27P, 5120×2880 native,
  2560×1440 UI mode at 75 Hz. There is no built-in/notched or mixed-display topology available.
- Installed clients detected read-only: ChatGPT/Codex (`com.openai.codex`), Claude
  (`com.anthropic.claudefordesktop`), IntelliJ IDEA, DataGrip, and Claude Code URL Handler.
  Detection is not a claim that their live hook/configuration matrices were modified or exercised.

## Evidence classification

| Area | Evidence available now | Classification |
|---|---|---|
| Unit/integration/security/migration/localization | 104 tests, 0 failures, 3 environment-gated skips | Automated fixture/current process |
| Soak runner mechanics | 20-second monitoring-only and Agent-enabled calibrations | Calibration only; never a 24-hour claim |
| Agent load | 200 synthetic Claude-compatible sessions in an isolated support/runtime directory | Fixture, not live client data |
| Native fullscreen | Retained WP4 100-cycle evidence on this same external notchless display | Current physical hardware |
| Notched/mixed displays | Synthetic topology coverage only | Hardware unavailable |
| Sleep/wake/lock/fast-user-switch | Policy/unit coverage; soak counters are instrumented | Real lifecycle run pending |
| VoiceOver manual traversal | Labels/render tests exist | Manual VoiceOver run pending |
| Permission denial/later authorization | Fail-closed unit paths | Real permission transition pending |
| Live third-party hooks | Apps detected only | Not exercised; user configs untouched |
| Remote SSH/tmux | Typed-plan and validation tests | No real remote host available |
| Different-user socket rejection | Peer-UID predicate and same-user real socket tests | Different-user OS account unavailable |

No accessibility, notification, automation, screen-recording, or other TCC permission was requested
or changed while collecting this inventory. No sleep, network disconnect, fast-user switch, hook
installation, or third-party configuration mutation was forced on the user's active machine.
