# N1KO-STATE agent instructions

## Required reading

For performance, UI/UX, settings, Agent Center, or top-of-screen surface work, read these files completely before editing code:

1. `docs/roadmap/README.md`
2. `docs/roadmap/01-audit-findings.md`
3. `docs/roadmap/02-target-architecture.md`
4. `docs/roadmap/03-fullscreen-window-design.md`
5. `docs/roadmap/04-delivery-plan.md`

`docs/roadmap/README.md` is the implementation status source of truth. Execute only its current **Next work package** unless the user explicitly changes scope. At the end of a work package, update its status and attach concrete verification evidence before selecting the next dependency-satisfied package.

## Non-negotiable constraints

- Preserve all current monitoring behavior, sampling semantics, history, alerts, fan control, and thermal-safety behavior unless the user explicitly approves a product change.
- Use the current N1KO-STATE checkout as the authority for existing behavior. Treat upstream projects as migration inputs, not as the application architecture.
- N1KO-STATE must retain one app lifecycle, one settings authority, one updater, and one presentation coordinator.
- Do not solve native-fullscreen flashing by showing a fullscreen-auxiliary desktop window and hiding it after detection. Follow the dual-window design in `03-fullscreen-window-design.md`.
- Product-facing names, links, bundle identifiers, paths, sockets, hook markers, update feeds, logs, and assets must use N1KO-STATE identity. Preserve legally required third-party licenses and notices.
- Do not introduce private `CGS*`/SkyLight APIs into the shipping path.
- Preserve unrelated user changes. Do not commit, push, tag, publish, notarize, or release unless the user explicitly asks.

## Verification baseline

Use checks appropriate to the work package. The repository's established local stack is:

```bash
swift build
plutil -lint Resources/Info.plist Localization/*/Localizable.strings
git diff --check
./build_app.sh --native --smoke
```

Add focused unit, integration, UI, performance, or fullscreen-transition tests when the changed behavior is not covered by these commands.
