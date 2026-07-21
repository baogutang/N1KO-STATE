# 03 — Notchless fullscreen window design

## Required user experience

Per display, not globally:

- A display with a physical camera housing may keep the normal top surface behavior appropriate to its safe-area geometry.
- A notchless display with “hide in fullscreen” enabled must not show the closed Island in a native fullscreen Space.
- Entering native fullscreen must not display the Island and hide it afterward. The persistent Island must never enter that Space.
- Deliberate top-edge hover may reveal an interactive Agent surface in fullscreen.
- Exiting fullscreen restores the desktop surface only after the normal Space is stable.
- Mixed built-in/external displays, horizontal/vertical arrangements, display reassignment, independent Spaces settings, sleep, wake, and fast transitions must not leak a panel onto the wrong screen.

There is no stable public API that exposes the menu bar's exact animation progress. The design therefore uses native Space membership for the baseline disappearance and treats top-edge reveal as a separate interaction driven by the same user gesture.

## Why the audited implementation flashes

At the pinned upstream snapshot:

1. the persistent panel uses `.fullScreenAuxiliary` and `.canJoinAllSpaces`;
2. it is shown as part of normal presentation setup;
3. Space/application notifications trigger a one-shot fullscreen check;
4. the view model later decides to hide;
5. the window controller calls `orderOut` after the window has already joined the fullscreen Space.

This ordering guarantees that some transitions can visibly show the panel before detection catches up.

Detection is also fragile because it samples a frontmost layer-zero window once and compares bounds across AppKit and Core Graphics coordinate conventions. Native fullscreen transitions expose unstable intermediate windows; pseudo-fullscreen may not change Spaces; helper processes may own the visible window; vertically arranged displays make coordinate mistakes more obvious.

## Two window roles

### DesktopIslandPanel

Purpose: persistent closed/open Island on ordinary desktop Spaces.

Collection behavior:

- `.moveToActiveSpace`
- `.stationary`
- `.ignoresCycle`
- `.fullScreenNone`
- deliberately no `.fullScreenAuxiliary`

The desktop coordinator orders the same window into the active ordinary Space only after ordinary
state stabilizes. A macOS 15.7.7 WindowServer harness proved that the earlier candidate
`.canJoinAllSpaces + .fullScreenNone` combination still exposed the panel after
`didEnterFullScreen`; that invalid calibration is retained in WP4 evidence. Replacing
`.canJoinAllSpaces` with `.moveToActiveSpace` produced zero visible desktop-panel samples across
100 real native-fullscreen enter/exit cycles. The invariant is more important than the original
candidate spelling: this window is not eligible to coexist with a native fullscreen primary
window, and WindowServer rather than a delayed detector excludes it from that Space.

### FullscreenRevealPanel

Purpose: deliberate, transient interaction after a top-edge dwell while the target display is fullscreen.

Rules:

- a separate `NSPanel` with `.fullScreenAuxiliary`;
- lazily constructed;
- default state is `orderOut` and it never becomes visible during ordinary transition detection;
- it may be shown only after the target display is stably fullscreen, user settings allow reveal, and a 150–200 ms top-edge dwell completes;
- pointer exit, Escape, display/Space change, session resign, screen sleep, or system sleep immediately orders it out;
- the global mouse monitor exists only during provisional/fullscreen states and is removed otherwise.

The two panels may reuse presentation models and content views, but they do not share the same `NSWindow` identity or collection behavior.

## Fullscreen state machine

```text
desktop
  | event that may change Space/window state
  v
entering
  | stable positive samples        | stable negative samples
  v                                v
fullscreen ----------------------> desktop
  | top-edge dwell                 | exit evidence
  v                                v
revealing -----------------------> exiting
  | pointer exit / Escape           | stable ordinary Space
  +--------------> fullscreen       v
                                   desktop

any state -- sleep/session resign --> suspended
suspended -- wake grace/reconcile --> entering or desktop
```

On a notchless display during uncertain transition state, the baseline policy is fail-closed: the desktop panel remains structurally absent from native fullscreen, and reveal is not allowed until positive evidence stabilizes.

## Detection inputs

Detection controls reveal eligibility and pseudo-fullscreen policy. It does not control the baseline native-fullscreen hiding.

Signals:

- `NSWorkspace.activeSpaceDidChangeNotification` as a request to reconcile;
- frontmost application changes;
- `NSApplication.didChangeScreenParametersNotification`;
- target-screen selection changes;
- screen/session sleep and wake;
- optional AX window/fullscreen changes after permission is granted;
- cancellable retry samples at approximately 0, 80, 180, 350, 700, and 1200 ms around transitions.

Use a generation token so a newer transition cancels stale retries. Enter and exit require consecutive agreeing samples or time-based hysteresis.

## Coordinate and display identity

Never compare `NSScreen.frame` coordinates directly with `kCGWindowBounds` from `CGWindowListCopyWindowInfo`.

Normalize through:

```text
NSScreenNumber
  -> CGDirectDisplayID
  -> CGDisplayCreateUUIDFromDisplayID
  -> CGDisplayBounds
```

The display UUID is the persisted identity. Core Graphics window coverage is evaluated against `CGDisplayBounds` in the same Quartz coordinate system. AppKit geometry remains inside presentation/layout code.

Basic window evidence may combine:

- frontmost PID or a known helper relationship;
- layer zero;
- target display coverage near 98.5%;
- small edge tolerance;
- AX fullscreen/frame evidence when authorized.

## Native fullscreen versus pseudo-fullscreen

Native fullscreen gets the strongest guarantee: zero baseline flash because the desktop window cannot join the Space.

Borderless/pseudo-fullscreen stays in an ordinary Space. Public APIs can detect its geometry quickly but cannot structurally exclude the desktop panel before the application changes its window. The shipping behavior should:

- react to frontmost/window evidence;
- hide fail-closed during a suspected transition;
- target a measured maximum delay of about 200 ms;
- document the limitation instead of introducing private `CGS*`/SkyLight APIs.

## Test matrix

### Displays

- built-in notched display;
- notchless external display;
- one built-in plus one external;
- two external displays;
- left/right and above/below arrangements;
- different scale factors and menu-bar display reassignment;
- “Displays have separate Spaces” enabled and disabled where the OS supports the configuration.

### Application modes

- Safari/Chrome native fullscreen;
- video-player native fullscreen;
- IDE native fullscreen;
- presentation mode;
- maximized but not fullscreen;
- borderless/pseudo-fullscreen application;
- helper-process-owned visible window;
- rapid app and Space switching.

### Lifecycle

- launch while target display is already fullscreen;
- settings toggle while fullscreen;
- target display connect/disconnect;
- sleep/wake and screen sleep/wake;
- user session resign/become-active;
- crash/relaunch of a monitored foreground app;
- 100 repeated native fullscreen enter/exit cycles.

## Acceptance gates

- Native fullscreen on a notchless display: 100 enter/exit cycles with no visible desktop-panel frame and no residual panel.
- Reveal panel never appears without completed top-edge dwell.
- Reveal dismissal works by pointer exit, Escape, Space exit, screen sleep, and session resign.
- The desktop panel returns only to the correct display after exit stabilization.
- No private `CGS*`/SkyLight symbol appears in the shipping target.
- Multi-display coordinate unit tests and an AppKit UI harness cover every arrangement above.
- Pseudo-fullscreen maximum observed hide delay is recorded, not assumed.
- Global monitors, retry tasks, and panels return to their baseline count after every transition sequence.
