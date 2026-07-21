# WP4 Ping-Island parity correction

Date: 2026-07-16; updated 2026-07-17

Superseded current-state note: this file records the rejected custom-shell correction through `v8`.
Production now runs the pinned source-level UI migration documented in
[the 2026-07-17 source-parity evidence](../2026-07-17/ping-island-source-parity.md).

Acceptance reference: `erha19/ping-island`
`da130d679e830894240e926184d29751dfd2def1` (v0.25.2).

## Why WP4 was reopened

The initial WP4 result used a floating `264 × 46` generic rounded card with a N1KO telemetry header
and nested card hierarchy. The user correctly rejected it: the requested product behavior was a
reproduction of Ping Island, with only the notchless fullscreen display/hide defect replaced by the
N1KO public-API dual-window design. Passing ownership and fullscreen tests did not satisfy that visual
acceptance gate.

## Rejected corrective implementation

- Replaced the generic card with a top-attached, pure-black Island shell.
- Compact geometry is `266 × 32`, centered at the display top with zero vertical inset.
- Closed radii are 6 pt inward shoulders and 14 pt lower curves; open radii are 19/24 pt.
- Hover activation is 240 ms. Hover and fullscreen reveal use a 600 pt panel; click uses a 520 pt
  panel. Height is bounded and derived from intervention/session content.
- Compact content follows the pinned hierarchy: original N1KO pixel glyph, activity text, and
  attention/session indicator.
- Expanded content follows the pinned hierarchy: session/provider header, small metadata pills,
  hover dashboard or click session list, completion state, and inline approval/question controls.
- Hover-opened panels collapse on pointer exit; click-opened panels collapse on Escape, explicit
  collapse, or outside click. The idle compact Island remains visible when presentation is enabled.
- AppKit window shadow was disabled and the window level aligned with the pinned top-surface behavior.
- The persistent desktop panel retains `.moveToActiveSpace + .fullScreenNone` and never gains
  `.fullScreenAuxiliary`. The separate reveal panel remains lazy and intent-gated.

No upstream font, sound, icon, mascot, screenshot, updater, telemetry, settings owner, lifecycle, or
window shell was copied. That boundary was legally conservative, but it also meant the provider
mascots and several characteristic interactions were omitted even though the pinned repository's
Apache NOTICE and the Silkscreen OFL provide a valid migration path when their obligations are met.
The result below is retained only as evidence of the rejected intermediate state.

## 2026-07-16 parity audit correction

The user correctly challenged whether this was a complete reproduction. It was not. Direct comparison
against pinned `da130d6` found the following missing or materially different behavior:

- route resolution for click, hover, attention, completion, pinned list, and chat;
- the provider-specific animated mascot family and exact pixel-status vocabulary;
- the hover conversation dashboard and attention-specific cards;
- completion notification queue, automatic presentation, hover pause, dismissal, and consumption;
- expandable parent/child session rows, inline actions, keyboard selection, and activation;
- the opened header's usage strip, temporary notification mute, and settings affordance;
- conversation/detail content and tool/history projection;
- long-press/drag detachment and the detached compact/expanded surface;
- dynamic measured content height and several empty/usage/notification presentation states.

The screenshots and passing tests in this document prove only the rejected shell's deterministic
behavior. They do not prove Ping-Island parity. WP4 stays open while these gaps are addressed through
N1KO's existing single session, settings, and presentation authorities. The sole intentional product
behavior difference remains the public-API dual-window fix for notchless native fullscreen.

## Current corrective implementation

The current production views are no longer the rejected shell described above. Source-by-source
comparison against pinned `da130d6` has added or corrected:

- exact `266 × 32` compact geometry, 19/24 opened radii, route priority, 240 ms hover activation,
  click/hover screen-width clamps, screen-height cap, and `closed height + content + 12` measurement;
- the complete default 13-provider Canvas mascot family and four-state motion vocabulary;
- source-style speaker/settings header controls, plain compact session count, usage strip, hover
  dashboard, expandable parent/child session list, inline focus/archive/conversation actions, and
  keyboard selection/activation;
- approval and blue question cards, four-option grid behavior, multi-select/other-answer handling,
  and authenticated response routing through the single N1KO Agent Core owner;
- completion priority/queue presentation, five-second dismissal, hover pause and immediate hover-exit
  consumption, plus manual-attention precedence without a completion timeout;
- the 0.35-second/8-point long-press gate, 20-point downward detachment threshold, exact Buddy
  metrics, pinned-list click behavior, hover preview, four-way bubble placement, and pet-anchor
  preservation during bubble resize;
- the pinned Codex detail hierarchy: back row, summary card, and one thread-result card with bounded
  recent conversation rows. The N1KO public-API dual-window fullscreen correction remains the sole
  intentional windowing difference.

## 2026-07-17 functional parity correction

The next source comparison closed the data/action gaps that could safely live inside N1KO's existing
authorities:

- Claude/Codex restoration now keeps at most 80 recent semantic items per session. Claude reads a
  complete-line-bounded 4 MiB transcript tail; Codex keeps first-line identity plus a 1 MiB rollout
  tail. Tool calls retain at most 2 KiB input and 8 KiB result, associate results by call ID, and show
  running/waiting/completed/failed states without carrying raw secrets into the presentation model.
- Codex initial restoration delivers one scan batch to the sole session store, performs one
  persistence write, and publishes one immutable snapshot. This preserves the richer history while
  avoiding one whole-store JSON encode per event.
- Provider usage now includes bounded five-hour/seven-day quota windows with remaining percentage and
  reset help text. Older replay cannot overwrite a newer captured window.
- Completion presentation now implements the pinned 60-second recency check, active-session blocking,
  queue revalidation, one-shot consumption, five-second timeout, hover pause, and hover-exit dismissal.
- A follow-up composer is visible only for a real enabled tmux target. It sends literal text and Enter
  as separate `/usr/bin/tmux` argument-vector calls, rejects NUL/oversized messages, and never invokes
  a shell. Sessions without a supported route show no simulated send action.
- Unified N1KO settings now support per-provider remapping across the 13 built-in mascot kinds,
  configurable system completion/attention sounds, and a local user-selected CESP/OpenPeon 1.x sound
  pack. The loader caps the manifest at 256 KiB, confines playable audio to the selected directory,
  rejects traversal/absolute/symlink escape, avoids immediate repeats, and falls back to system sound.
- Visible settings copy and runtime type names use N1KO/Agent identity. Upstream naming remains only
  in legal attribution and source modification comments.

## Superseded `v8` deterministic visual evidence

These 2x captures were rendered from the former custom production views using immutable session
fixtures. They are retained as intermediate evidence and are not current acceptance captures:

- [Compact Island](ping-island-parity-v8/agent-island-compact.png)
- [Click-expanded approval](ping-island-parity-v8/agent-island-click-expanded.png)
- [Hover dashboard](ping-island-parity-v8/agent-island-hover-dashboard.png)
- [Session list with quota windows](ping-island-parity-v8/agent-island-session-list.png)
- [Question form](ping-island-parity-v8/agent-island-question.png)
- [Session detail, rich tool result, and real-route composer](ping-island-parity-v8/agent-island-conversation.png)
- [Detached Buddy and pinned list](ping-island-parity-v8/agent-island-detached-expanded.png)
- [All 13 default provider mascots](ping-island-parity-v8/agent-island-provider-mascots.png)
- [Fullscreen reveal route](ping-island-parity-v8/agent-island-fullscreen-reveal.png)

Earlier `ping-island-parity` through `v7` directories are retained as intermediate/rejection evidence;
they are not the current acceptance captures.

## Remaining parity gaps

This implementation still cannot honestly be called a complete source-runtime reproduction:

1. N1KO observes external Agent sessions and does not own a native Claude/Codex runtime. The pinned
   source's launch/terminate actions therefore have no safe N1KO owner; terminating an externally
   owned process or presenting a nonfunctional action would violate the boundary instead of adding
   parity.
2. Codex app-server ingress remains a protocol adapter without a concrete authenticated sender.
   Follow-up is real for capability-enabled tmux sessions, but non-tmux/Codex app-server sending is
   unavailable rather than faked.
3. Direct live visual/interaction acceptance by the user remains open. Deterministic production-view
   captures and automated interaction tests do not substitute for that product gate.

## Verification status

- `swift build`: passed after the current correction.
- `swift test --filter WP4AgentSurfaceTests`: 22 executed, 21 passed, 1 expected opt-in live
  WindowServer skip, 0 failures; the capture run generated all nine `v8` images.
- The ingress/store/security/shutdown focused run executed 23 tests with 0 failures. The added batch
  regression test proves 82 historical events yield one persistence save and one final snapshot.
- `swift test`: 122 executed, 119 passed, 3 expected opt-in/environment skips, 0 failures. Fan
  control, thermal safety, history, monitoring lifecycle, provider, migration, security, and prior
  package regression tests remain green.
- Geometry tests cover top attachment, source radii/timing, natural-height calculation, narrow-screen
  click/hover width clamps, screen-height cap, detachment thresholds, four-way placement, and anchor
  preservation.
- Localization/plist lint, `git diff --check`, the N1KO identity gate, and strict ad-hoc code-sign
  verification pass. `./build_app.sh --native --smoke` rebuilt the arm64 Release app. The first run
  exposed a real 101.7% startup regression: initial rollout recovery encoded the complete store once
  per event. After scan batching it passed with an 8.9% six-second sample; at 35 seconds three
  instantaneous samples were 0.0%, 6.7%, and 8.0% while normal monitor/Agent work continued. This was
  a short startup regression check, not a restarted Menu Bar occupancy matrix or soak.
- `otool` reports `minos 12.0`; shipping source and undefined-symbol scans are clean for private
  CGS/SLS/SkyLight APIs. The app bundle includes NOTICE plus Ping-Island Apache, Sparkle, and SMCKit
  licenses. The earlier 100-cycle native fullscreen and live pseudo-fullscreen latency evidence
  remains retained in `results.md`; the dual-window code was not changed by this correction.

WP4 stays **In Progress / Next** because the remaining functional parity gaps above are real. WP6
remains paused behind this gate. No completion, release, or user acceptance is claimed.
