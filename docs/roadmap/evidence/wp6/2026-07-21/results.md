# WP6 release-candidate evidence — 2026-07-21

Status: **Automated gates pass; residual long-duration/manual evidence remains**

Released version: v1.0.18 / build 118 from source commit `4ff76b1`; generated appcast commit `c348a93`.

## Automated validation

| Gate | Result |
|---|---|
| `N1KO_RUN_CODEX_APP_SERVER_ACCEPTANCE=1 swift test` | 138 tests executed, 3 explicit environment skips, 0 failures; installed Codex acceptance passed |
| `swift build` | Passed with no Swift warnings/errors |
| `./build_app.sh --native --smoke` | Native arm64 Release assembly and launch smoke passed |
| plist/localization | `Resources/Info.plist` and all three `Localizable.strings` files lint; localization keys are unique |
| identity/update feed | N1KO product scan and `appcast.xml` feed consistency pass |
| single owners | One `@main`, AppDelegate, settings controller, updater, presentation coordinator and AgentSessionCoordinator |
| legal/assets | Apache LICENSE/NOTICE, Sparkle, SMCKit notices bundled; 13 approved WAV files match the pinned SHA-256 manifest |
| public API | Shipping source and linked-symbol scans contain no private CGS/SLS/SkyLight entry point |
| compatibility/signature | Main app and bridge have `minos 12.0`; strict deep ad-hoc signature verification passes |
| diff hygiene | `git diff --check` passes |
| GitHub publication | Actions run `29799932353` passed Xcode 15.4 universal build, DMG verification, signed Sparkle appcast publication and GitHub Release creation |

The three skips are the unmounted installer-DMG filter check, sustained libproc comparison, and live
pseudo-fullscreen WindowServer latency gate. They are recorded as skips, not passes.

The first tagged CI attempts exposed source-compatibility differences hidden by the local Xcode 26
toolchain: the WP4 harness needed `-parse-as-library`, and Xcode 15.4 required older-compatible
concurrency isolation and character-splitting syntax. The compatibility-only fixes are commits
`77abfef`, `296497c`, and `4ff76b1`. Relevant local build/test gates were rerun as the fixes landed;
final Actions run `29799932353` passed every release step. The published assets are
`N1KO-STATE.dmg` (13,004,469 bytes), `N1KO-STATE-sparkle.zip` (11,676,228 bytes), and `appcast.xml`
with the v1.0.18 enclosure URL and EdDSA signature.

## Isolated calibration

Runner: `scripts/run_wp6_soak.sh`; 30-second measurement, 3-second warm-up, 2-second sampling,
isolated preferences/history/runtime, `N1KO_PERF_HEADLESS=1`, and coexistence with the user's visible
N1KO-STATE instance. The headless path removes the temporary status item and does not install
presentation surfaces, so it does not occupy the Menu Bar or animate hidden Island views.

| Scenario | Awake avg CPU | Awake wakeups/s | Avg power | Footprint delta | Sessions | Resource growth |
|---|---:|---:|---:|---:|---:|---|
| monitoring-only | 0.091% | 1.569 | 1.84 mW | -0.422 MB | 0 | thread -9; FD/socket/Agent/surface 0 |
| Agent-enabled | 0.086% | 1.409 | 1.74 mW | -0.500 MB | 200 | thread -9; FD/socket/Agent/surface 0 |

Both analyses report `CALIBRATION_PASS`. Evidence is stored under
`calibration-final/{monitoring-only,agent-enabled}`.

An earlier Agent calibration correctly failed at 2.62% awake CPU and 70.77 wakeups/s. A process
sample showed the supposedly headless process had still installed the Ping mascot `TimelineView`;
200 synthetic sessions kept the hidden presentation tree animating. The harness was corrected to
skip presentation installation only when `N1KO_PERF_HEADLESS=1`. Normal application presentation,
monitor sampling, histories, alerts, fan control and thermal safety were unchanged. The final rerun
above closes this harness regression.

## Release authorization and residual risk

The user explicitly authorized version upgrade, remote push and GitHub automated publication after
validation. v1.0.18 was published successfully on 2026-07-21; the following evidence boundary still
does not become a pass merely because publication completed:

- the required monitoring-only and Agent-enabled **24-hour** runs have not completed;
- the prior 1,093-awake-second run remains partial only;
- physical notched/mixed/external display, Intel/macOS 12, different-user account, real SSH,
  VoiceOver, explicit lock/unlock and fast-user-switch matrices are unavailable on this host;
- no Developer ID signing/notarization is performed by the local validation path; the existing
  GitHub workflow publishes the project's established release format.

WP6 therefore remains the sole Next package for post-release residual evidence even though all
remaining code work, locally available automated release gates, and the authorized GitHub
publication are complete.
