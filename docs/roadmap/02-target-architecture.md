# 02 — Target architecture

## First-principles boundaries

N1KO-STATE has four different kinds of truth:

1. **Machine truth:** acquired hardware and operating-system observations.
2. **Safety truth:** alert and fan-control state that must continue even when UI is hidden.
3. **Agent truth:** normalized coding-session events, interventions, usage, associations, and lifecycle.
4. **Presentation truth:** immutable projections displayed by the menu bar, Quick Panel, Agent Island, and settings preview.

No view should acquire machine truth. No window controller should own safety truth. No upstream AppDelegate should coexist with N1KO lifecycle. No raw sampler object should independently publish into multiple unrelated view trees.

## Ownership map

```text
N1KO AppDelegate
├── MonitorSamplingCoordinator
│   ├── SamplingPlanner
│   ├── module samplers/executors
│   ├── SafetyPolicy
│   └── MonitorSnapshotStore
├── AgentSessionCoordinator
│   ├── AgentIngressCoordinator
│   │   ├── HookSocketServer
│   │   ├── Codex/App-server and rollout ingestion
│   │   └── provider/runtime adapters
│   ├── AgentSessionStore
│   ├── AgentUsageService
│   └── AgentMigrationService
├── PresentationCoordinator
│   ├── MenuBarStatusController
│   ├── QuickPanelController
│   └── AgentSurfaceCoordinator
│       ├── DesktopIslandPanel
│       └── FullscreenRevealPanel
├── AppPreferences
└── UpdateController
```

N1KO-STATE remains the owner at every top-level boundary.

## Monitoring architecture

### SamplingPlan

On each scheduler wake, the main actor computes a plan from monotonic deadlines and explicit needs:

- menu-bar projection requirements;
- visible Quick Panel modules;
- long-history requirements;
- alert requirements;
- fan-safety requirements;
- battery/lock/sleep/low-power state;
- forced refresh after wake or presentation.

Avoid tick-count rules such as `% 3` or `% 5`; their real duration changes when the user's refresh interval changes.

### Samplers

- CPU and memory keep the current Mach sources.
- Network keeps `getifaddrs`-based rate semantics but executes away from the main actor and caches interface metadata.
- GPU keeps the current cached IOAccelerator service and discovery backoff.
- Disk volume metadata remains mount/unmount driven; rate acquisition runs away from the main actor.
- IOHID/SMC retain dedicated serialization, cache stable product/name metadata, and keep fan safety independent from visibility.
- Process sampling moves to libproc deltas with a `ps` fallback only when required.

### Snapshot commit

Every module produces one immutable `Equatable` snapshot. A generation commit contains:

- generation identifier and monotonic timestamp;
- values used by menu bar and Quick Panel;
- freshness per module;
- alert/safety state;
- optional presentation-ready formatted projection or stable render signature.

The UI receives either the whole coherent generation or a scoped, equatable projection. It never combines half-old and half-new monitor objects.

## Agent integration boundary

The audited upstream is a complete application, not a widget: approximately 74,000 lines of production Swift, 131 production Swift files, and 85 root test files at the pinned snapshot. Whole-repository merging would import a second lifecycle, settings model, updater, window system, product identity, telemetry, and deployment assumptions.

### Port or reuse

- event, phase, provider, tool-result, and session models;
- session store, association, completion, intervention, and lifecycle logic;
- Claude/Codex ingestion, parsers, watchers, native runtime, and usage/cache logic;
- hook-envelope normalization and client-specific hook semantics;
- relevant logic and integration tests.

Selected reused files remain under Apache-2.0 and carry a prominent modification notice.

### Rework behind N1KO protocols

- hook installers and bridge binary;
- Unix socket runtime and connection authentication;
- terminal/IDE focus service;
- remote/SSH and tmux integration;
- provider discovery and capability registry;
- file/cache/runtime paths and diagnostics.

The domain may not directly depend on a settings singleton, an AppKit window singleton, Sparkle, telemetry, or a concrete SwiftUI view.

### Rewrite in N1KO

- AppDelegate/application entry point;
- window and surface coordination;
- top-of-screen UI and all monitor/Agent composition;
- settings UI and persistence façade;
- onboarding, permissions, About, updates, telemetry/privacy choices;
- icons, fonts, sounds, mascots, copy, links, bundle identifiers, feed URLs, log subsystems, and runtime names.

### First integration slice and final scope

The first vertical slice should prove Claude and Codex session ingestion, normalization, lifecycle, attention, and usage without any Island UI. Later parity packages add every remaining provider and optional focus/remote capability. Staging is not permission to shrink the final requested scope; it keeps each change measurable and reversible.

## Runtime security

- Do not reuse a world-accessible `/tmp` socket or broad permissions.
- Use a short per-user path under `$TMPDIR` with parent directory `0700` and socket `0600`.
- Validate the peer user identifier. Sensitive approval/answer paths should add a per-install secret or equivalent authenticated envelope.
- Hook installers must edit only exact managed entries and preserve unrelated user configuration byte-for-byte where possible.
- A new bridge must successfully receive a probe event before old managed references are removed.
- Apple Events and Accessibility are requested only when a selected function needs them. Neither is a prerequisite for basic Agent event ingestion or structural native-fullscreen hiding.

## Unified settings repository

Use one external façade with domain-scoped stores and a versioned migration ledger:

```text
settings.schemaVersion
general.*
appearance.*
monitor.*
menuBar.*
quickPanel.*
safety.*
agent.presentation.*
agent.behavior.*
agent.integration.*
agent.sound.*
alerts.*
update.*
migration.*
```

Complex values such as screen selections, anchors, shortcuts, remote hosts, and migration ledgers use Codable types rather than loosely related string keys.

Migration requirements:

1. back up current N1KO defaults;
2. migrate existing N1KO keys idempotently without changing defaults or behavior;
3. optionally detect old Agent-app defaults/cache/config only after user authorization;
4. migrate associations and usage cache, not transient window expansion state;
5. take over only precisely marked managed hook entries;
6. prove new ingress before removing old references;
7. retain rollback data and a migration ledger for at least two public versions.

## Settings information architecture

One native Settings window and router handles `Command-,`, status menu Settings, About, permission deep links, and Agent setup.

Recommended native sidebar destinations:

1. **General** — login item, language, appearance.
2. **Display** — menu bar, Quick Panel, Agent Island, shared module order and static previews.
3. **Monitoring** — modules, sampling profiles, history.
4. **Safety** — sensors, helper, fans, alerts, notification permission.
5. **Agent Center** — session behavior, presentation, shortcuts, privacy.
6. **Integrations** — clients, hooks, terminal/IDE, remote capabilities.
7. **Advanced** — updates, diagnostics, migration, third-party notices, About.

Use `NavigationSplitView`/`List(selection:)` or another standard macOS navigation container. There is one window identity, current-pane title, restored last pane, and control-level search. Do not keep a parallel SwiftUI Settings scene and manual settings window.

## Visual direction: Calm Telemetry

The monitoring, Quick Panel, and Settings visual language is a quiet native telemetry instrument,
not a web dashboard. The Agent Island is the deliberate exception: its shell, compact/hover/click
hierarchy, and interaction timing run from the pinned Ping-Island view/controller/model source behind
N1KO-owned identity, settings, Agent, focus, localization, sound, and window coordination adapters.

- System window and Popover materials are the base surfaces.
- Use at most one grouped secondary surface; remove nested card-on-card layers.
- One accent color represents selection and primary action.
- Green, orange, and red are reserved for normal/warning/danger and are always paired with text, icon, or shape.
- Module identity uses SF Symbols, names, and stable values. Module chart colors must not be confused with alert colors.
- Default body text is approximately 13 pt; secondary text 11–12 pt; content text does not fall below 10 pt.
- Numeric telemetry uses monospaced digits and reserved width to preserve menu-bar stability.
- Spacing tokens: 4, 8, 12, 16, 24. Control radius 8; larger surface radius 12; icon-button hit area 28 by 28.

### Quick Panel

- top health summary: CPU, memory, and thermal status;
- stable 44–52 pt module rows with icon, title, micro-trend, and monospaced value;
- at most one expanded module detail at a time;
- destructive process/fan actions live in expanded detail and require confirmation;
- Settings, About, and Quit live in native menus or a restrained overflow, not as equally prominent header icons.

### Agent Island

The Island is an event and attention surface for active sessions, approvals, questions, completions,
and a jump back to the correct terminal/window. It is not a second full monitor dashboard. Its
acceptance reference is Ping Island at `da130d6`: a top-attached pure-black compact notch, inward top
shoulders, larger lower curves, provider/mascot-like leading identity, center activity text, trailing
attention/session state, hover dashboard, click session list, and inline intervention controls.
N1KO migrates the pinned Apache-2.0 UI/model/controller source, including provider mascot Canvas
drawings, with retained license/NOTICE and prominent markers on every modified same-path file. It
does not instantiate the upstream app lifecycle or settings/session/update/telemetry owners. The
only copied binary resources are the 13 pinned WAV files explicitly approved by the user and covered
by the retained Apache LICENSE/NOTICE; upstream fonts, product icons, screenshots, product identity,
and other unproven assets remain excluded. On
notchless displays, the public-API dual-window design in `03-fullscreen-window-design.md` replaces
upstream fullscreen window membership so the ordinary Island cannot flash in native fullscreen.

## Motion system

Only user intent and discrete semantic state changes animate. Raw telemetry samples do not restart long springs.

- click feedback: 0.10–0.12 seconds, opacity/color only;
- disclosure: 0.18–0.22 seconds, coordinated height and opacity;
- deliberate Island compact/expanded transition: the pinned behavior's single spring around response 0.42 and damping 0.82;
- continuous visible data: no first-frame animation; optional 0.12–0.18 second interpolation for small changes only;
- alerts: one finite emphasis, never `repeatForever`;
- hidden/occluded/suspended surfaces: no display-link animation;
- Reduce Motion: no spring, scale, offset, blur, or loop; direct state change or crossfade at or below 0.10 seconds.

Quick Panel state is explicit:

```text
hidden -> presenting -> visibleFirstSnapshot -> visibleLive
visibleLive -> interacting -> dismissing -> hidden
```

The Hosting Controller persists across cycles. First snapshot lands without animation. Only `visibleLive` may perform lightweight interpolation.

## Deployment compatibility

N1KO-STATE currently declares macOS 12 and Swift tools 5.9. The audited upstream shipping target declares macOS 14 and uses newer SwiftUI/concurrency patterns in several places.

WP0 must compile a representative Agent domain slice against the chosen N1KO toolchain and deployment target. Do not silently raise the minimum version as a side effect of migration. If the project keeps macOS 12, newer features require availability isolation or backporting; if the minimum is raised, document and obtain explicit product approval.

## Licensing and identity

N1KO original code can remain MIT. Directly reused upstream code is Apache-2.0:

- distribute the Apache license;
- retain relevant NOTICE attribution;
- preserve relevant source notices;
- mark modified files prominently;
- do not imply upstream endorsement or reuse its trademarks as N1KO product identity.

The app bundle and Advanced/About settings include readable third-party notices. Product-facing identity is fully N1KO. If legal attribution is forbidden from containing the upstream name, direct source reuse is not an available route and the behavior must be independently reimplemented.
