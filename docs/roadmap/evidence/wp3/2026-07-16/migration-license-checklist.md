# WP3 Agent migration and license checklist

Authoritative upstream input: `erha19/ping-island`
`da130d679e830894240e926184d29751dfd2def1` (v0.25.2). The local input checkout
was verified at that exact commit before migration.

## Migrated behavior

| Pinned upstream input | N1KO-owned destination | WP3 disposition |
|---|---|---|
| `Models/SessionEvent.swift`, `SessionPhase.swift`, `SessionProvider.swift`, `SessionState.swift` | `AgentModels.swift`, `AgentEvents.swift`, `AgentSessionStore.swift` | Adapted and substantially rewritten into a smaller immutable Claude/Codex domain; no UI convenience state |
| `Services/Session/ConversationParser.swift` | `ClaudeTranscriptParser` | Adapted parser semantics behind a Foundation-only API; bounded transcript read is coordinator-owned |
| `Services/Codex/CodexRolloutParser.swift`, `CodexThreadSnapshot.swift` | `CodexRolloutParser`, `CodexRolloutIngressSource` | Adapted with the macOS 12-compatible string path; event-driven watcher, bounded first-line/tail restore, and lifecycle projection are N1KO changes |
| `Services/Codex/CodexAppServerMonitor.swift` | `CodexAppServerParser`, `CodexAppServerTransport`, `CodexAppServerIngressSource` | Reworked behind an injected transport; no upstream singleton, websocket owner, subprocess owner, or UI dependency |
| `Services/Hooks/HookSocketServer.swift` | `AgentHookSocketServer` | Rewritten with N1KO path, peer UID check, 0700/0600 policy, install secret, and response-channel ownership |
| `Services/State/SessionAssociationStore.swift`, `ToolEventProcessor.swift` | `AgentSessionStore` | Adapted identity association, intervention, completion, archive, attention, and idempotent restore behavior |
| `Services/Usage/*` selected in WP0 | `AgentUsage`, parser usage extraction, `AgentUsageSummary` | Adapted cumulative Claude/Codex token semantics; no UI presenter or upstream cache path |
| `Services/Runtime/*`, session watchers, runtime registry | `AgentIngressCoordinator`, lifecycle policy, protocol resources | Rewritten around N1KO lifecycle and shutdown accounting; no second app lifecycle |
| Relevant Claude/Codex/session/usage/runtime tests | `Tests/N1KOAgentCoreTests` | Behavior-level tests rewritten for N1KO protocols, security rules, immutable snapshots, and shutdown gates |

Files in the WP0 `reuse` set that are not needed by the first Claude/Codex lifecycle projection remain
unmigrated rather than being pulled in speculatively. In particular, no upstream chat UI model,
tool-result presentation model, focus/tmux/remote service, or extra provider implementation enters WP3.

## License actions

- Adapted source files carry a prominent N1KO modification notice and identify the pinned input.
- `ThirdPartyLicenses/Ping-Island-Apache-2.0.txt` is byte-identical to the pinned 201-line
  `LICENSE.md` (`cmp -s` passes).
- `THIRD_PARTY_NOTICES.md` retains the relevant Ping Island copyright/attribution and identifies
  the modified Agent Core scope.
- `build_app.sh` copies both files into
  `N1KO-STATE.app/Contents/Resources/ThirdPartyNotices/`; the native bundle contains the 201-line
  license and readable notice.
- No upstream font, icon, sound, mascot, screenshot, updater asset, or other resource was copied.
  The upstream OFL font notice is therefore not applicable to the WP3 bundle.
- Existing N1KO MIT, SMCKit MIT, and Sparkle notices remain intact.

## Identity and exclusion audit

- Runtime subsystem, Application Support directory, socket, secret, queue labels, diagnostics,
  and hook wire contract use `com.n1ko.state.agent` / `N1KO-STATE` identity.
- The shipping core has no import or reference to AppKit, SwiftUI, an upstream AppDelegate,
  settings window, updater, analytics/telemetry service, `CGS*`, `SLS*`, SkyLight, or display-link API.
- The only upstream product name in shipping source is inside the required Apache modification
  notices; ordinary runtime strings and paths are N1KO-only.
- No hook takeover or legacy config mutation is performed in WP3. Managed installation, conflict
  handling, proof event, rollback, and legacy migration remain WP5 work.
