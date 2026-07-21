# WP6 rollback and recovery runbook

This runbook is for a signed release candidate or later installation. It does not authorize a
release, publication, or mutation of the current user's integrations during WP6 verification.

## Safe application rollback

1. Quit N1KO-STATE normally. Do not use `kill -9`: normal termination flushes history and asks the
   fan helper to return every fan to automatic mode; the helper's connection-invalidation handler
   remains the last safety backstop.
2. Confirm no manual fan target remains in N1KO-STATE before replacing the application.
3. Preserve these directories before troubleshooting or downgrading:
   - `~/Library/Application Support/N1KO-STATE`
   - `~/Library/Logs/N1KO-STATE`
   - the `com.n1ko.state.monitor` defaults domain
4. Replace only the application bundle with the previously verified N1KO-STATE build. Do not copy
   an upstream application shell, updater, helper, settings directory, or runtime socket over it.
5. Launch once and verify monitoring values, history, alerts, fan automatic state, Agent enablement,
   and the configured update channel before deleting any backup.

## Preference recovery

Schema-2 migration creates an exact private backup before mutation at:

`~/Library/Application Support/N1KO-STATE/Migration/preferences-before-schema-2.plist`

The migration ledger is:

`~/Library/Application Support/N1KO-STATE/Migration/preferences-ledger.json`

Before importing an older plist, export the current defaults to a separate file and quit the app.
Importing a plist is a deliberate whole-domain replacement, so it must never be performed as an
automatic repair. Keep the ledger and both before/after backups with the incident record. On the
next launch verify menu metrics, module ordering, alert thresholds, sampling mode, Agent flags, and
fan settings; if any semantic value is unclear, restore the newer export instead of guessing.

## Agent integration rollback

- Preferred removal path: Settings → Agent Center → Provider Integrations → Remove. Removal touches
  only the exact N1KO-managed entry for that profile and preserves unrelated user configuration.
- Every managed-hook change creates a 0600 exact per-file backup under
  `~/Library/Application Support/N1KO-STATE/Migration/HookBackups` and an entry in
  `~/Library/Application Support/N1KO-STATE/Migration/hook-ledger.json`.
- A proof failure or concurrent edit restores the exact pre-change bytes automatically. Never
  overwrite a provider file from a backup when its current hash differs; preserve both versions and
  resolve the conflict explicitly.
- The ownership lease at `Migration/integration-owner.json` prevents two live applications from
  repeatedly reinstalling hooks. Do not delete it while either owner is running.
- Legacy import is read-only. There is no legacy-source rollback because N1KO-STATE never edits the
  legacy source; N1KO's imported session/usage state can be backed up or reset independently.

## Agent runtime and diagnostics recovery

- The per-user runtime directory and install secret are 0700/0600 and recreated if absent. Never
  copy an install secret between users or machines.
- A stale socket may be removed only after confirming N1KO-STATE and its bridge are not running.
- Diagnostic archives are local, 0600, explicitly user-created, redacted, and never uploaded
  automatically. Review them before sharing and delete them using normal Finder controls when no
  longer needed.

## Recovery acceptance check

Recovery is complete only when monitoring and history are coherent, alerts remain configured, fan
control is automatic unless the user deliberately selects otherwise, Agent hooks pass a fresh
proof or are cleanly removed, no response capability survives restart, and the app still has one
settings authority, updater, lifecycle owner, and presentation coordinator.
