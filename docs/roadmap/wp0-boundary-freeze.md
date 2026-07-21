# WP0 boundary freeze and migration decisions

Date: **2026-07-15**

N1KO-STATE authority: **`09cde29c24d20f8b97f0fd2995a686fac0cb3ab7`**

Pinned Agent input: **`erha19/ping-island` `da130d679e830894240e926184d29751dfd2def1` / v0.25.2**

## Decisions

### Minimum macOS

Keep **macOS 12** as the deployment target. The representative Agent model/store/parser spike uses
the current Swift 6.1.2 compiler in Swift 5 language mode with target
`arm64-apple-macosx12.0`. The unmodified slice exposed one macOS 13-only call in
`CodexRolloutParser.swift`; replacing the multi-character `String.split` call with
`components(separatedBy:)` made the selected slice typecheck. This is a small backport, not evidence
for raising the whole product to macOS 14.

Evidence: [Agent compatibility spike](evidence/wp0/agent-compatibility-spike.md).

### First Agent release slice

The first vertical slice is **Claude + Codex Agent Core without Island UI**:

- ingest and normalize Claude and Codex session events;
- restore, merge, complete, archive, and attention-mark sessions;
- calculate usage and publish immutable Agent snapshots;
- keep runtime paths, socket security, settings, lifecycle, updater, and diagnostics N1KO-owned.

Gemini, Qwen, Kimi, Hermes, OpenCode, Pi, Qoder/CodeBuddy families, IDE focus, remote/SSH, tmux,
floating pet/mascots, and top-of-screen presentation stay in later dependency-satisfied packages.
They remain in final parity scope; this is release slicing only.

### Legal route and product identity

Use selected Apache-2.0 source files where the migration inventory says `reuse`, with the full
Apache license, retained NOTICE attribution, preserved source notices, and a prominent N1KO
modification marker. The repository and shipped notices may therefore contain the upstream project
name in legal attribution. Product-facing UI, assets, executable/bundle names, paths, sockets, hook
markers, logs, update feeds, and ordinary product documentation remain N1KO-only.

If a future product decision requires literal zero occurrence of the upstream name even in legal
files, every `reuse` row must change to independent `rewrite`; direct reuse would no longer be
allowed.

## File-level migration inventory

The generated inventory covers **all 452 files** at the pinned commit:

| Disposition | Files | Meaning |
|---|---:|---|
| `reuse` | 21 | Selected Agent logic/legal files; Apache/OFL duties remain |
| `adapt-behind-protocol` | 75 | Port behavior behind N1KO-owned interfaces and paths |
| `rewrite` | 62 | N1KO owns the application, presentation, settings, fullscreen, and UI replacement |
| `exclude-until-parity` | 294 | Not admitted to the first slice; reconsider only in its later package |

Source of truth: [wp0-upstream-file-inventory.tsv](wp0-upstream-file-inventory.tsv). Regenerate with
`scripts/generate_agent_migration_inventory.sh`; the script pins the same commit and refuses to
follow upstream `main` implicitly.

## License, font, sound, logo, and resource inventory

### Current N1KO-STATE distribution

| Item | Location | License/ownership evidence | WP0 disposition |
|---|---|---|---|
| N1KO-STATE source | `LICENSE`, `Sources/N1KOState`, helper/shims | MIT project license | Retain |
| SMCKit | `Sources/SMCKit` | MIT notice embedded in source and `LICENSE` | Retain notices and modification marker |
| Sparkle 2.9.3 | SwiftPM artifact/checkouts | Sparkle license plus bundled third-party terms | Retain dependency license in final in-app notices |
| N1KO app icon | `Resources/AppIcon.icns` | Present in current product repository; separate provenance record absent | Retain current asset; document provenance before WP6 |
| README banner and donation QR | `docs/assets` | Documentation assets; separate provenance record absent | Do not automatically copy into Agent product surfaces |
| System fonts/SF Symbols/default alert sounds | AppKit/SwiftUI system resources | Platform-provided | Preferred for first slice; no new bundled font/sound |

### Pinned Agent input

| Item | Count/type | Evidence | Disposition |
|---|---:|---|---|
| Swift/source/test/config files | Apache-2.0 | Upstream `LICENSE.md` and `NOTICE` | Reuse/adapt/rewrite only as classified; notices required for copied source |
| Silkscreen font + OFL text | 2 files | Upstream `Silkscreen-OFL.txt` | Do not migrate; Calm Telemetry uses system typography |
| App/provider logos and icon assets | Asset catalog and documentation images | No per-asset provenance found in the pinned tree | **Unsafe to migrate without further proof**; use N1KO-owned or provider-authorized replacements |
| WAV sounds | 13 files | No per-sound provenance/license record found beyond repository-level Apache text | **Unsafe to migrate without further proof**; replace or separately clear rights |
| Mascot GIFs/product screenshots/DMG art | Documentation images | Product/trademark content, no per-asset clearance | Exclude; create N1KO-owned assets only if later scope requires them |

No upstream source or asset is copied into the shipping target during WP0.

## Frozen architectural exclusions

- Do not import the upstream AppDelegate, app entry point, settings singleton/window, updater,
  telemetry, window manager, top-of-screen UI, branding, or release pipeline.
- Keep one N1KO AppDelegate, one settings authority, one updater, and one presentation coordinator.
- Keep the desktop/fullscreen dual-window design and public-API-only shipping path for WP4.
- Keep existing monitoring, history, alert, manual fan, curve, and thermal-safety semantics unchanged.
