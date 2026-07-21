# WP4 closure evidence — 2026-07-21

Status: **Complete at code and automated acceptance level**

Base checkout: `09cde29`; release candidate: v1.0.18 working tree.

## Closed functional boundaries

| Previously open boundary | Implemented result |
|---|---|
| Native Claude launch/input/termination | `AgentNativeRuntimeController` launches the installed Claude CLI inside a N1KO-owned pseudo-terminal, validates the working directory, sends follow-up input through the owned file descriptor, and terminates only sessions created by N1KO. |
| Codex authenticated outbound sender | `CodexAppServerStdioTransport` owns `codex app-server --stdio`, initializes with the existing Codex authentication state without reading credentials, carries notifications and approval responses, starts/archives native threads, and sends non-tmux follow-up via `turn/steer` or `turn/start`. |
| Unsafe termination scope | Ownership is recorded per native session; N1KO cannot archive or kill an externally owned session/PID. |
| Process-tree/tmux focus suppression | `AgentProcessTreeBuilder` uses public `/bin/ps` process information, terminal ancestry, TTY and active tmux-pane queries. The tmux executable is resolved from an explicit path, `PATH`, and standard Homebrew/system locations rather than a nonexistent hard-coded path. |
| Swift 6 warning debt | Touched notification/fullscreen callbacks now enter `MainActor` explicitly; the evidence sampler is explicitly Sendable and no-op `await` calls were removed. The final build/test log has no Swift warning. |

The coordinator remains the sole session/runtime/response owner. The Codex child and native runtime
are registered with its existing lifecycle manager. Disabled Agent mode starts neither transport nor
native runtime. No arbitrary PID termination, fixed loopback listener, credential copy, private
WindowServer API, second session store, updater, settings authority, or presentation coordinator was
added.

## Ping Island source and fullscreen boundary

- Production desktop/reveal routes still instantiate the migrated
  `NotchViewController + NotchView`; floating mode still uses
  `DetachedIslandWindowController + DetachedIslandPanelView`.
- Compact/click/hover/detail/question/completion/detachment/mascot/sound settings continue to use the
  reviewed source-level migration recorded in the 2026-07-17 mapping. The rejected generic N1KO
  surface is not restored to the production route.
- Desktop and detached ordinary-Space windows retain `.moveToActiveSpace + .fullScreenNone` and do
  not use `.fullScreenAuxiliary`. Only the normally hidden reveal panel is fullscreen-eligible after
  stable classification and deliberate top-edge dwell.
- The retained physical 100-cycle notchless result remains zero desktop-panel samples in native
  fullscreen. This package did not rerun a disruptive live Menu Bar/fullscreen occupancy loop.

## Direct verification

Commands and results:

```text
swift test
  138 tests, 3 explicit environment skips, 0 failures; installed Codex acceptance included

N1KO_RUN_CODEX_APP_SERVER_ACCEPTANCE=1 swift test --filter AgentNativeRuntimeTests/testInstalledCodexAppServerInitializesAndStopsWhenExplicitlyEnabled
  installed Codex 0.145.0-alpha.18 initialized over owned stdio and stopped; 1 passed

swift test --filter AgentNativeRuntimeTests/testClaudePseudoTerminalLaunchInputAndOwnedTermination
  pseudo-terminal launch/input/owned termination; 1 passed

./build_app.sh --native --smoke
  native Release assembly and launch smoke passed

./scripts/run_wp6_release_gate.sh
  identity, owner, legal, sound hash, public API, minos 12.0, signature and diff gates passed
```

Focused tests also cover Codex response payloads, native ownership, non-tmux messaging, invalid CWD,
executable resolution, process-tree terminal/tmux selection, Qwen concurrent same-workspace session
identity, provider parity, and the 100-cycle fullscreen state machine.

## Evidence boundary

The user explicitly requested completion and release after the source-parity correction, which
resolves the former manual acceptance blocker for the release decision. No claim is made that this
machine exercised a physical notched display, mixed-display layout, Intel/macOS 12 host, VoiceOver,
or every installed third-party Agent client. Those are retained as WP6 residual release risks.
