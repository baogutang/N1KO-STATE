# N1KO-STATE evolution roadmap

Status: **WP4/WP5 development is complete; WP6 residual long-duration/manual evidence is the sole Next package**

Last updated: **2026-07-21**

Current checkout audited: **v1.0.18 release source `4ff76b1`; main includes the generated appcast commit `c348a93`**

Upstream Agent capability snapshot audited: **`erha19/ping-island` `c9148fc6a66a98f62dc1cac8fde415c2be9f2233` / v0.26.0**

## Purpose

This directory is the implementation source of truth for two connected outcomes:

1. Reduce N1KO-STATE resource use without weakening monitoring behavior, history, alerts, fan control, or thermal safety; redesign the Quick Panel, settings, visual system, and motion behavior as one coherent native macOS experience.
2. Add AI coding-session awareness and top-of-screen interaction capabilities to N1KO-STATE while keeping N1KO-STATE as the sole application architecture, fixing notchless-display fullscreen behavior, unifying settings and interaction design, and removing upstream product identity from the N1KO product layer.

The desired product is not two applications placed side by side. It is one quiet macOS utility with three coordinated planes:

- a monitoring and safety plane;
- an Agent event and session plane;
- a presentation plane for the menu bar, Quick Panel, Agent Island, and settings.

## Required documents

- [01 — Audit findings](01-audit-findings.md): current runtime/code evidence and root causes.
- [02 — Target architecture](02-target-architecture.md): ownership, module boundaries, settings, UI, motion, migration, and licensing.
- [03 — Fullscreen window design](03-fullscreen-window-design.md): the required notchless-display behavior and test matrix.
- [04 — Delivery plan](04-delivery-plan.md): dependency-ordered work packages and acceptance gates.
- [Research sources](research-sources.md): Apple documentation and inspected open-source references.
- [Next-session prompt](NEXT_SESSION_PROMPT.md): copy-ready prompt for a new Codex task.

## Locked decisions

These decisions remain in force unless the user explicitly changes them:

1. **No monitoring capability tradeoff.** Optimize ownership, lifecycle, scheduling, publication, allocation, and rendering before changing sampling semantics.
2. **One display snapshot generation.** Menu bar, Quick Panel, settings preview, and all monitor visualizations render a coherent generation rather than independently reading monitor objects.
3. **One application authority.** N1KO-STATE retains one `AppDelegate`, one settings repository/window, one Sparkle updater, and one presentation coordinator.
4. **Extract the Agent domain; run the pinned Island source inside the N1KO shell.** Reuse or port event/session/hook/runtime/usage logic and tests, and migrate the pinned Ping-Island view/controller/model sources behind N1KO-owned session, settings, update, focus, localization, sound, screen, and presentation adapters. Do not merge the upstream AppDelegate, updater, settings authority, session store, branding, telemetry, or lifecycle.
5. **Structural fullscreen exclusion.** The persistent desktop Island never joins native fullscreen Spaces. A separate, normally hidden auxiliary panel handles deliberate top-edge reveal.
6. **Public API shipping path.** Private `CGS*`/SkyLight APIs may be studied as references but are not allowed in production.
7. **Product-layer zero upstream branding.** Product UI, executable names, bundle IDs, runtime paths, socket names, hook markers, logs, update feeds, assets, and ordinary product documentation use N1KO identity. Legally required third-party attribution remains in licenses/notices. Legacy migration may retain narrowly scoped old identifiers until its removal window closes.
8. **No big-bang merge.** Every work package leaves the main branch buildable and independently verifiable.
9. **Ping-Island parity with a structural fullscreen fix.** The pinned `da130d6` UI behavior remains the source-level acceptance reference because the audited v0.26.0 update did not change the Island UI core. N1KO selectively carries the v0.26.0 provider changes while keeping its own identity and public-API dual-window implementation; on notchless displays the persistent desktop Island is structurally absent from native fullscreen and the separate reveal panel appears only after deliberate top-edge intent.

## Decisions resolved in WP0

- Preserve macOS 12; the representative Agent slice typechecks after one documented backport.
- First Agent release slice is Claude + Codex Agent Core. Remote/SSH, tmux, IDE integration,
  optional surfaces/mascots, and remaining providers stay in later parity packages.
- Selected Apache-2.0 reuse is allowed only with required LICENSE/NOTICE and N1KO modification
  markers. Product-facing identity remains N1KO-only; unproven upstream assets are excluded.

## Work-package status

| Package | Status | Depends on | Outcome |
|---|---|---|---|
| WP0 — Baseline and boundary freeze | Complete | — | Reproducible metrics, signposts, compatibility decision, reuse/license inventory |
| WP1 — Monitoring performance foundation | Complete | WP0 | Coherent generations, lifecycle-safe sampling, libproc comparison, bounded histories |
| WP2 — Native UI, motion, and settings foundation | Complete | WP1 | One settings window, persistent Quick Panel host, design/motion system, accessible previews |
| WP3 — Agent Core | Complete | WP2 | Session/event/hook/runtime/usage domain owned by N1KO, initially without Island UI |
| WP4 — Agent Island and fullscreen behavior | Complete | WP3 | Ping-Island UI/interaction parity, native Claude/Codex operation, exact focus suppression, N1KO dual-window fullscreen |
| WP5 — Full integration parity and migration | Complete (refreshed through v0.26.0) | WP4 | 21 provider profiles, focus/remote features, safe hook takeover, legacy migration |
| WP6 — Release hardening | **In Progress / Next (residual evidence)** | WP5 | Automated release gates pass; two 24-hour soaks and unavailable hardware/manual matrices remain |

## Next work package

**WP6 — Release hardening (residual evidence).**

WP4 is closed at the code and automated-acceptance level. Production desktop/reveal surfaces still
host the migrated `NotchViewController + NotchView`, and floating mode hosts
`DetachedIslandWindowController + DetachedIslandPanelView`; the rejected N1KO approximation is not
in the production route. The remaining functional gaps were implemented on 2026-07-21: N1KO now
owns native Claude pseudo-terminal sessions, an authenticated Codex app-server stdio child for
native launch/archive and non-tmux follow-up, and public process-tree/tmux focus suppression. Swift
6 actor-isolation warnings in the touched notification/fullscreen paths were removed. See
[WP4 closure evidence](evidence/wp4/2026-07-21/results.md).

The Ping Island v0.26.0 audit found no Island UI-core, sound, LICENSE, or NOTICE delta. N1KO therefore
keeps the already reviewed UI source mapping and selectively migrates Qoder CN desktop/CLI support;
the provider registry now has 21 reproducible profiles. The upstream Qwen same-workspace fix was
already structurally satisfied by N1KO's provider-plus-session key. No upstream product asset or
architecture was imported. See [v0.26.0 audit](evidence/wp5/2026-07-21/upstream-v0.26.0-audit.md).

The automated WP6 release candidate passes the complete 138-test suite, native Release/smoke,
localization, legal/sound hash, identity, single-owner, public-API, macOS 12 minimum, signature, and
diff gates. Isolated 30-second calibrations pass without occupying the user's Menu Bar: monitoring
averaged 0.091% awake CPU and 1.57 wakeups/s; Agent Core with 200 sessions averaged 0.086% and 1.41,
with no growing thread, FD, socket, Agent-resource, or surface-resource counts. See
[2026-07-21 WP6 evidence](evidence/wp6/2026-07-21/results.md).

The user explicitly authorized publication with that evidence boundary. GitHub Actions run
`29799932353` then built and verified the Xcode 15.4 arm64+x86_64 DMG, generated and published the
signed Sparkle appcast, and published the v1.0.18 GitHub Release from source commit `4ff76b1` on
2026-07-21. Publication does not convert missing evidence into a pass. The sole Next package is still
WP6 until both independent 24-hour runs and the unavailable notched/mixed-display, Intel/macOS 12,
different-user, real-SSH, VoiceOver, lock/unlock, and fast-user-switch matrices are completed. The
older 1,093-awake-second run remains partial and is not represented as a 24-hour result.

## Status update rules

At the end of each work package:

1. Change its status in the table to `Complete` only when every listed gate has direct evidence.
2. Add a short evidence section under that package in `04-delivery-plan.md`: commands, test counts, Instruments scenario names/results, and any remaining caveats.
3. Mark exactly one dependency-satisfied package as `Next`.
4. If a decision changes the target architecture, update all affected roadmap documents in the same change.

Tests passing is not by itself proof of performance, UI, fullscreen, migration, or license completion. Each requirement needs evidence at its own level.
