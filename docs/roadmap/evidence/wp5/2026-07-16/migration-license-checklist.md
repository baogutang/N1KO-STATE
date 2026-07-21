# WP5 migration, identity, and license checklist — 2026-07-16

| Item | Disposition | Direct evidence / retained boundary |
|---|---|---|
| Compatibility input | Pinned and read-only | Upstream checkout is clean at `da130d679e830894240e926184d29751dfd2def1`; N1KO checkout remains the behavior authority |
| Provider/client registry | N1KO-owned rewrite | 19 profiles and fixtures live in `N1KOAgentCore`; no upstream AppDelegate, updater, settings, window manager, UI shell, or telemetry was merged |
| Managed bridge and hook installer | N1KO-owned rewrite | `n1ko-agent-bridge`, N1KO paths, marker, socket, secret, lease, backups, and ledgers; no upstream executable or runtime directory is shipped |
| Hook configuration formats | Compatibility knowledge only | Provider JSON/TOML/plugin shapes are emitted by new N1KO code and tested in isolated temporary homes |
| Existing Apache-derived Agent files | Attribution retained | `AgentEvents`, `AgentModels`, `AgentParsers`, and `AgentSessionStore` retain prominent modification comments; NOTICE names the pinned input commit |
| Apache license | Bundled | `ThirdPartyLicenses/Ping-Island-Apache-2.0.txt` is copied to `Contents/Resources/ThirdPartyNotices/Licenses/` |
| Sparkle 2.9.3 license | Corrected and bundled | Complete locked-checkout license, including external component terms, is in `ThirdPartyLicenses/Sparkle-LICENSE.txt` and copied into the app |
| SMCKit license | Corrected and bundled | MIT text is in `ThirdPartyLicenses/SMCKit-MIT.txt`, in addition to existing source headers and Settings attribution |
| Upstream fonts, sounds, logos, icons, mascots, updater, telemetry, assets | Excluded | No rights-unproven asset was migrated; optional provider companions use Apple system symbols only |
| Current N1KO preferences | Versioned migration | Schema 2 backs up the exact current persistent domain before mutation, writes 0600 backup/ledger under a 0700 migration directory, never overwrites a current choice, and is idempotent |
| Previous N1KO preferences | Narrow compatibility import | Only absent allowlisted keys from `com.n1kostate.menubar.app2026` are imported; obsolete presentation keys are removed by the one migrator |
| Legacy Agent data | Optional read-only import | Requires explicit confirmation; imports associations, profile selection, aggregate usage/cache only; source files remain untouched |
| Excluded legacy data | Never imported | Credentials, secrets, hook ownership, passwords, transient window/Island expansion state, and unrelated defaults |
| Managed-hook takeover | Transactional | Exact per-file 0600 backups, staged N1KO entries, bounded real bridge probe, post-probe hash check, then exact legacy-reference removal |
| Repeat/upgrade/downgrade | Ledger controlled | Same schema is idempotent, upgrades are recorded, downgrades are blocked, removals and rollbacks have file/hash records |
| Concurrent changes | Fail closed | Install, removal, and rollback do not overwrite a file replaced or edited by the user after staging |
| New/legacy app coexistence | Lease controlled | Running exact legacy bundle or another live N1KO owner blocks hook writes; stale owner PID can be reclaimed |
| Temporary legacy identity | Migration-only allowlist | Exact identifiers exist only in `AgentLegacyImport.swift` and `AgentManagedHooks.swift`; allowlist removal is scheduled at settings schema 4 |
| Product identity | N1KO-only | `scripts/run_wp5_identity_gate.sh` accepts only legal comments/notices and the two migration files; product Resources, Localization, executable names, paths, sockets, markers, bundle IDs, logs, feed, and README are clean |
| Private window APIs | Excluded | Source and linked-symbol scans are clean for private `CGS*`, `SLS*`, and SkyLight shipping calls |
| Update ownership | One existing controller | Only `UpdateController` owns Sparkle; install relaunch is deferred while an Agent session is active and resumed once after all sessions become idle |
| Release action | Not authorized / not performed | No commit, push, tag, Developer ID signing, notarization, update publication, DMG publication, or release |

## Retention and rollback locations

- N1KO preferences: `~/Library/Application Support/N1KO-STATE/Migration/preferences-ledger.json`
  and `preferences-before-schema-2.plist`.
- Managed hooks: `Migration/hook-ledger.json`, `Migration/HookBackups/`, and
  `Migration/integration-owner.json` under the N1KO application-support directory.
- Optional legacy import: `Migration/legacy-import-ledger.json`; source legacy defaults/cache/files
  are never deleted or edited.

All migration and integration mutations are initiated by explicit user actions. Basic Agent ingress,
monitoring, history, alerts, fan control, and thermal-safety behavior require none of these optional
permissions or migrations.
