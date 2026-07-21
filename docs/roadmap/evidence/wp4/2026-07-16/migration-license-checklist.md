# WP4 migration and license checklist — 2026-07-16

| Item | Disposition | Evidence |
|---|---|---|
| Upstream route/view behavior | Selected Apache-2.0 adaptation | `AgentIslandDesign.swift`, `AgentSurfaceViews.swift`, and `AgentSurfaceCoordinator.swift` adapt the pinned route hierarchy, measured sizing, notification lifecycle, and detached Buddy layout with prominent modification notices |
| Provider mascot Canvas source | Selected Apache-2.0 adaptation | `PingIslandMascotView.swift` carries the complete pinned 13-provider Canvas drawings and four-state motion vocabulary behind N1KO provider/settings adapters and a prominent modification notice |
| Upstream AppKit window/lifecycle shell | Excluded | `N1KOWindowCore` panels, presentation coordinator, settings authority, updater, AppDelegate, and public-API fullscreen state machine remain N1KO-owned |
| Upstream fonts, product icons, sounds, screenshots, telemetry, and other assets | Excluded | Shipping bundle inputs contain none; the Silkscreen font and upstream audio/image resources were not migrated |
| Upstream session/store ownership | Not duplicated | WP4 consumes WP3 immutable snapshots and routes responses back to the sole WP3 coordinator |
| Source license boundary | Apache-2.0 plus N1KO project source | Selected Ping-derived UI/mascot source retains Apache notice/license and modification markers; `N1KOWindowCore`, fullscreen state machine, N1KO data/response adapters, tests, and harness remain N1KO-owned |
| Apple frameworks/SF Symbols | System APIs/resources | AppKit, ApplicationServices, CoreGraphics, Combine, SwiftUI; no redistributed third-party asset |
| Existing Apache-derived WP3 files | Unchanged obligation | Existing Apache 2.0 license, NOTICE, and N1KO modification markers remain bundled |
| New third-party dependency | None | SwiftPM adds a local N1KO target and test harness only |
| Private API | Excluded | Shipping scan clean for `CGS*`, `SLS*`, and SkyLight |
| Product identity | N1KO-only | No upstream product name, link, bundle ID, feed, runtime path, socket, hook marker, product icon, or screenshot enters the product layer; Ping Island appears only in legal/source attribution and roadmap evidence |

WP4 changes no managed hook, legacy preference domain, provider install, or third-party configuration.
Those migration actions remain exclusively in WP5.
