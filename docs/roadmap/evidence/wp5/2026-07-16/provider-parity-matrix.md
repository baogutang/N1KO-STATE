# WP5 provider and client parity matrix — 2026-07-16

Authority snapshot: current N1KO-STATE checkout `09cde29c24d20f8b97f0fd2995a686fac0cb3ab7`
plus retained WP0–WP5 work. Compatibility input was rechecked at the clean, pinned upstream commit
`da130d679e830894240e926184d29751dfd2def1`; no upstream application shell was merged.

“Fixture pass” means a provider-specific payload is normalized through the production parser and
the registry, profile identity, session identity, and owner fields are asserted. “Shape pass” means
the managed installer wrote the production configuration into an isolated home directory and the
provider-specific JSON/TOML/plugin shape and exact N1KO marker were asserted. It does not claim that
the corresponding third-party application was installed or launched on this Mac.

| Profile / audited client boundary | Provider | Managed integration | Response / optional capabilities | Direct evidence | Result |
|---|---|---|---|---|---|
| Claude Code; Claude Desktop discovery | Claude | `.claude/settings.json`, Claude-compatible event set | inline response, terminal, tmux, SSH plan, system symbol | fixture + JSON shape + real bridge/socket probe | Pass |
| Codex App / CLI | Codex | `.codex/hooks.json`, Codex JSON-RPC ingress | inline response, terminal, tmux, SSH plan, system symbol | fixture + JSON shape + Codex parser tests | Pass |
| Gemini CLI | Gemini | `.gemini/settings.json`, Gemini hook events | terminal, system symbol | fixture + JSON shape + real Gemini bridge probe | Pass |
| Qwen Code | Qwen | `.qwen/settings.json`, extended Claude-compatible events | inline response, terminal, tmux, SSH plan, system symbol | fixture + JSON shape + owner/navigation assertions | Pass |
| Kimi CLI | Kimi | `.kimi/config.toml`, TOML hook blocks | inline response, terminal, SSH plan, system symbol | fixture + TOML shape/takeover preservation | Pass |
| Hermes | Hermes | `.hermes/plugins/n1ko-state/` plugin + manifest | terminal, SSH plan, system symbol | fixture + Python/plugin manifest shape | Pass |
| Pi Agent | Pi | `.pi/agent/extensions/n1ko-state/` plugin | terminal, SSH plan, system symbol | fixture + TypeScript plugin shape | Pass |
| OpenCode desktop / CLI | OpenCode | N1KO JS plugin plus exact activation entry | inline response, terminal/IDE, SSH plan, system symbol | fixture + plugin/activation shape | Pass |
| OpenClaw | OpenClaw | `.openclaw/hooks/n1ko-state/` plus exact activation entry | terminal, SSH plan, system symbol | fixture + TS/HOOK.md/activation shape | Pass |
| Qoder IDE | Qoder | shared `.qoder/settings.json` managed profile | terminal/IDE, tmux, system symbol | fixture + shared-config preservation shape | Pass |
| Qoder CLI | Qoder CLI | shared `.qoder/settings.json` managed profile | inline response, terminal, tmux, SSH plan, system symbol | fixture + shared-config preservation shape | Pass |
| QoderWork | QoderWork | `.qoderwork/settings.json` | terminal/IDE, tmux, system symbol | fixture + JSON shape | Pass |
| CodeBuddy desktop | CodeBuddy | shared `.codebuddy/settings.json` managed profile | terminal/IDE, tmux, system symbol | fixture + shared-config preservation shape | Pass |
| CodeBuddy CLI | CodeBuddy CLI | shared `.codebuddy/settings.json` managed profile | inline response, terminal, tmux, SSH plan, system symbol | fixture + shared-config preservation shape | Pass |
| WorkBuddy | WorkBuddy | `.workbuddy/settings.json` | terminal/IDE, tmux, system symbol | fixture + JSON shape | Pass |
| Cursor | Cursor | `.cursor/hooks.json`, direct command entries | terminal/IDE, system symbol | fixture + direct-entry JSON shape | Pass |
| GitHub Copilot / Copilot for Xcode | Copilot | `.github/hooks/n1ko-state.json`, flat bash entries | terminal/IDE, system symbol | fixture + versioned flat-bash shape | Pass |
| Trae | Trae | runtime detection/focus only; config writes rejected | terminal/IDE, system symbol | fixture + explicit runtime-only rejection | Pass at declared boundary |
| JetBrains Agent/plugin family | JetBrains | runtime detection/focus only; config writes rejected | terminal/IDE, system symbol | fixture + explicit runtime-only rejection | Pass at declared boundary |

## Matrix-level assertions

- `AgentIntegrationRegistry` has exactly **19** audited profiles: **17** managed hook/plugin profiles
  and **2** explicitly runtime-only profiles. `Fixtures/Agent/wp5-provider-events.json` has an exact
  one-to-one profile fixture set.
- All 17 managed profiles install with `--managed-by com.n1ko.state.agent --profile <id>` and
  N1KO-owned bridge paths. Runtime-only profiles fail closed instead of writing speculative client
  configuration.
- The real `N1KOAgentBridge` executable was launched against a real private Unix socket and a
  Gemini probe reached provider-aware ingress with an authenticated acknowledgement.
- Terminal/IDE focus uses public `NSWorkspace` APIs; tmux targets are strict-character validated
  and invoked as `/usr/bin/tmux` arguments without a shell. Remote SSH is an opt-in, non-shell,
  host-fingerprint-carrying command-plan boundary; no remote host was contacted in WP5.
- The optional visual companion uses SF Symbols only and remains off by default. No third-party
  logos, icons, sounds, fonts, or mascot resources were imported.

Automated matrix source: `AgentProviderParityTests`, `AgentManagedHookTests`,
`AgentBridgeIntegrationTests`, `AgentRuntimeSecurityTests`, and `WP5IntegrationMigrationTests`.
