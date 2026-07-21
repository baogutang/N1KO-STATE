#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT/docs/roadmap/evidence/wp4/$(date -u +%Y%m%dT%H%M%SZ)/fullscreen-harness}"
mkdir -p "$OUTPUT_ROOT"

{
    echo "checkout=$(git rev-parse HEAD)"
    echo "branch=$(git branch --show-current)"
    echo "macos=$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    echo "hardware=$(sysctl -n hw.model)"
    echo "swift=$(swiftc --version 2>&1 | head -1)"
    echo "native_cycles=100"
    system_profiler SPDisplaysDataType -detailLevel mini
} > "$OUTPUT_ROOT/metadata.txt"

N1KO_RUN_PSEUDO_FULLSCREEN_LATENCY=1 swift test \
    --filter WP4AgentSurfaceTests/testPseudoFullscreenHideAndStableDetectionLatencyWhenOptedIn \
    2>&1 | tee "$OUTPUT_ROOT/pseudo-fullscreen.txt"

swift build --product N1KOWP4FullscreenHarness
N1KO_NATIVE_FULLSCREEN_CYCLES=100 \
N1KO_NATIVE_FULLSCREEN_OUTPUT="$OUTPUT_ROOT/native-fullscreen-100-cycles.json" \
swift run --skip-build N1KOWP4FullscreenHarness \
    2>&1 | tee "$OUTPUT_ROOT/native-fullscreen-100-cycles.txt"

rg -n "WP4_PSEUDO_FULLSCREEN|desktopFramesInFullscreen|failed|error:" \
    "$OUTPUT_ROOT" > "$OUTPUT_ROOT/summary-signals.txt" || true
