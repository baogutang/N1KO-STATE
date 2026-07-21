# Ping Island v0.26.0 selective migration audit — 2026-07-21

Status: **Audited and selectively migrated**

| Item | Previous pin | Audited upstream |
|---|---|---|
| Tag | v0.25.2 | v0.26.0 |
| Commit | `da130d679e830894240e926184d29751dfd2def1` | `c9148fc6a66a98f62dc1cac8fde415c2be9f2233` |
| Delta | — | 4 commits, 30 files, approximately +733/-60 |

## Compatibility decision

The v0.26.0 delta does not change the migrated Island UI core (`NotchView`, `NotchViewModel`,
desktop/reveal/detached controllers, or mascot settings), the 13 sound files, Apache LICENSE, or
NOTICE. Replacing the reviewed source tree wholesale would therefore add risk without improving UI
parity and remains prohibited.

The meaningful capability changes were handled as follows:

| Upstream change | N1KO action | Result |
|---|---|---|
| Qoder CN desktop client | Add `qoderCN`, managed `.qoder-cn/settings.json` profile and `com.aliyun.lingma.ide` bundle/helper identity | Migrated; desktop events are notify-only, matching upstream response limits |
| Qoder CN CLI | Add `qoderCNCLI` profile on the same managed configuration with inline response capability | Migrated and fixture-backed |
| Qoder CN visual asset | Upstream uses an SF Symbol/no separately licensed extracted product asset | Use system symbol only; no upstream logo copied |
| Qwen same-workspace session collision fix | Compare against N1KO store identity | Already satisfied: N1KO keys provider plus session and never evicts another session solely for sharing `cwd` |

The reproducible provider registry and fixture matrix now contain **21 profiles**. A focused
regression test keeps two simultaneous Qwen sessions in the same working directory distinct.

## Migration and license inventory

- New source logic is implemented behind existing N1KO provider, registry, terminal and session
  adapters; no upstream AppDelegate, settings repository, store, updater, analytics, branding,
  runtime path, hook marker, or application architecture was merged.
- No new third-party binary, font, icon, image, audio, or telemetry asset was imported.
- Existing Ping Island Apache-2.0 LICENSE/NOTICE and modification markers remain complete and
  bundled. Since the v0.26.0 selective delta adds no asset or license text, no new license file is
  required.
- Product identifiers, paths, hooks, sockets, logs and links remain N1KO-facing.

Verification: provider parity tests (five focused cases), the full 138-test suite, identity gate,
private-API gate, legal bundle gate and sound SHA-256 manifest all pass.
