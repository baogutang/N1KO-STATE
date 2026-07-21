# N1KO-STATE 1.0.18 roadmap release notes

Release status: **authorized by the user on 2026-07-21 with documented residual evidence risk**.
The publication copy is `.github/release-notes/v1.0.18.md`; this roadmap file retains the engineering
scope and evidence boundary.

## Highlights

- Reworked the monitoring runtime around coherent display snapshots and lifecycle-aware scheduling
  while preserving monitoring semantics, 24-hour history, alerts, fan control, and thermal safety.
- Rebuilt Quick Panel, settings, native motion, accessibility labels, three-locale layout, and the
  Agent Center under one N1KO-STATE window/settings/presentation architecture.
- Added N1KO-owned Agent session awareness, authenticated per-user hook ingress, provider parity,
  explicit focus/tmux/verified-SSH capabilities, safe managed-hook takeover, and versioned migration.
- Added a dual-window Agent Island design: the persistent desktop panel is structurally excluded
  from native fullscreen Spaces; a normally hidden public-API reveal panel handles deliberate
  top-edge interaction.
- Added local-only redacted diagnostic export, private runtime files, count-only soak diagnostics,
  and explicit third-party notices for the selected Apache-2.0 work, Sparkle, and SMCKit.

## Compatibility and safety

- Minimum deployment target remains macOS 12.0.
- N1KO-STATE remains the sole lifecycle, settings, updater, and presentation authority.
- Agent behavior and optional capabilities remain user-controlled; remote actions require explicit
  enablement and a verified host plan.
- Normal quit and helper invalidation retain fan automatic-reset protection.

## Evidence boundary

The locally available automated gates and final isolated calibrations pass, but both independent
24-hour soaks and unavailable physical/manual matrices remain WP6 Next work. Short calibration values
must not be turned into 24-hour product claims. The release request authorizes publication with that
known boundary; it does not change missing evidence into a pass.
