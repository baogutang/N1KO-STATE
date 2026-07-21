# WP4 source migration and license checklist — 2026-07-17

| Item | Disposition | Evidence |
|---|---|---|
| Pinned UI source | Source-level Apache-2.0 migration | 72 files: 41 exact, 24 adapted same-path, 7 N1KO boundary adapters |
| Docked/reveal runtime | Pinned view/controller inside N1KO windows | `NotchViewController` + `NotchView`; N1KO owns desktop/reveal panel membership and lifecycle |
| Detached runtime | Pinned controller/view with fullscreen adaptation | `DetachedIslandWindowController` + `DetachedIslandPanelView`; ordinary-Space `.fullScreenNone` replaces upstream fullscreen membership |
| Session/settings/update/telemetry ownership | Not duplicated | N1KO adapters project the sole authorities; upstream owners are not instantiated |
| Behavior/display settings | Source-extracted into the sole N1KO settings window | auto-hide, suppression, auto-open/collapse, notch-or-floating presentation, density/size/content/usage controls; presentation mode drives the existing N1KO window owner |
| Focus/actions | Adapted behind N1KO authority | approval/answer/archive/follow-up/focus route to N1KO capability owners; unsupported native runtime actions remain disabled |
| Apache license | Included and byte-identical | `Ping-Island-Apache-2.0.txt`, SHA-256 `d8b6cb6571c65d3dfaa4983b2ba20d19887ab5d1269e963eb3817ceb0c0e1447` |
| Upstream NOTICE | Included and byte-identical | `Ping-Island-NOTICE.txt`, SHA-256 `ad648dd4a96456b339021d2c730ed535759432e9468c04d310ba602ef2c7b42a` |
| Modification markers | Complete | every modified same-path pinned Swift file begins with the N1KO modification notice |
| Pinned audio | Included after explicit user approval | all 13 `PingIsland/Resources/Sounds/*.wav` files are byte-identical; `Resources/Sounds/SHA256SUMS`, the asset test, and the release bundle gate verify the complete set; Apache LICENSE/NOTICE retained |
| Fonts, product icons/screenshots, other assets | Excluded | no upstream font/product-image resource is bundled; unproven per-asset provenance is not assumed |
| Product identity | N1KO-only | identity gate passes; upstream executable strings remain only in legal/source attribution and exact legacy migration constants |
| Private API | Excluded | source and linked-symbol scans clean for `CGS*`, `SLS*`, and SkyLight |
| Existing dependencies | Unchanged | Sparkle and SMCKit full licenses remain bundled; no new package dependency added |

No upstream AppDelegate, settings repository/window, updater, telemetry client, session store, runtime
paths, hook owner, or product identifier was merged.
