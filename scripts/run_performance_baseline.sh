#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_DEVELOPER_DIR="${BUILD_DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
export DEVELOPER_DIR="$BUILD_DEVELOPER_DIR"

SCENARIO="${1:-menu-bar-only}"
WARMUP_SECONDS="${WARMUP_SECONDS:-120}"
MEASUREMENT_SECONDS="${MEASUREMENT_SECONDS:-600}"
REPETITIONS="${REPETITIONS:-3}"
SAMPLE_SECONDS="${SAMPLE_SECONDS:-10}"
SKIP_BUILD="${SKIP_BUILD:-0}"
REQUIRE_XCTRACE="${REQUIRE_XCTRACE:-0}"
ALLOW_CONCURRENT_N1KO="${ALLOW_CONCURRENT_N1KO:-0}"
XCTRACE_TEMPLATE="${XCTRACE_TEMPLATE:-Time Profiler}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT/docs/roadmap/evidence/wp0/$STAMP/$SCENARIO}"

case "$SCENARIO" in
    menu-bar-only|agent-core-idle|agent-surface-hidden|quick-panel-cards|quick-panel-gauges|settings-overview|settings-menu-bar|settings-popover|settings-sampling|settings-sensors|settings-alerts|settings-agent-center|settings-advanced|settings-used-then-closed|panel-settings-100-cycles) ;;
    *)
        echo "Unknown scenario: $SCENARIO" >&2
        exit 64
        ;;
esac

for value in "$WARMUP_SECONDS" "$MEASUREMENT_SECONDS" "$REPETITIONS" "$SAMPLE_SECONDS"; do
    [[ "$value" =~ ^[0-9]+$ ]] || { echo "Timing and repetition values must be integers" >&2; exit 64; }
done
(( MEASUREMENT_SECONDS > SAMPLE_SECONDS + 1 )) || {
    echo "MEASUREMENT_SECONDS must be at least SAMPLE_SECONDS + 2" >&2
    exit 64
}

mkdir -p "$OUTPUT_ROOT"
if [[ "$SKIP_BUILD" != "1" ]]; then
    DEVELOPER_DIR="$BUILD_DEVELOPER_DIR" ./build_app.sh --native
fi

APP_EXE="$ROOT/build/N1KO-STATE.app/Contents/MacOS/N1KOState"
FIXTURE="$ROOT/Fixtures/Performance/baseline-all-modules-2s.plist"
PROC_METRICS="$(mktemp -t n1ko-proc-metrics)"
DEVELOPER_DIR="$BUILD_DEVELOPER_DIR" xcrun clang -O2 "$ROOT/scripts/performance/proc_metrics.c" -o "$PROC_METRICS"

EXISTING_N1KO_PIDS="$(pgrep -x N1KOState | tr '\n' ',' | sed 's/,$//' || true)"
if [[ -n "$EXISTING_N1KO_PIDS" && "$ALLOW_CONCURRENT_N1KO" != "1" ]]; then
    echo "N1KOState is already running (pid(s): $EXISTING_N1KO_PIDS); quit it before an isolated baseline or set ALLOW_CONCURRENT_N1KO=1 for a non-gating smoke run" >&2
    exit 73
fi

XCTRACE_DEVELOPER_DIR="${XCTRACE_DEVELOPER_DIR:-$(env -u DEVELOPER_DIR xcode-select -p 2>/dev/null || true)}"
if [[ -n "$XCTRACE_DEVELOPER_DIR" ]] && DEVELOPER_DIR="$XCTRACE_DEVELOPER_DIR" xcrun xctrace version >/dev/null 2>&1; then
    TRACE_BACKEND="xctrace:$XCTRACE_TEMPLATE"
else
    TRACE_BACKEND="sample+signpost-counters"
    if [[ "$REQUIRE_XCTRACE" == "1" ]]; then
        echo "xctrace is required but full Xcode/Instruments is not installed" >&2
        exit 69
    fi
fi

APP_DURATION_SECONDS="$MEASUREMENT_SECONDS"
if [[ "$TRACE_BACKEND" == xctrace:* ]]; then
    # `xctrace` starts after the synchronous stack sample. Keep the target
    # alive long enough for the trace to reach its own time limit and save
    # cleanly before normal app termination.
    APP_DURATION_SECONDS=$((MEASUREMENT_SECONDS + SAMPLE_SECONDS + 30))
fi

DEFAULTS_DOMAIN="com.n1ko.state.monitor"
BACKUP_DIR="$(mktemp -d -t n1ko-state-defaults)"
BACKUP="$BACKUP_DIR/defaults.plist"
HAD_DEFAULTS=0
if defaults export "$DEFAULTS_DOMAIN" "$BACKUP" >/dev/null 2>&1; then
    HAD_DEFAULTS=1
fi
CURRENT_PID=""
TOP_PID=""
XCTRACE_PID=""

stop_process() {
    local pid="$1"
    [[ -n "$pid" ]] || return 0

    kill "$pid" >/dev/null 2>&1 || true
    for _ in {1..50}; do
        if ! kill -0 "$pid" >/dev/null 2>&1; then
            wait "$pid" >/dev/null 2>&1 || true
            return 0
        fi
        sleep 0.1
    done

    kill -KILL "$pid" >/dev/null 2>&1 || true
    wait "$pid" >/dev/null 2>&1 || true
}

cleanup() {
    trap - EXIT INT TERM
    stop_process "$TOP_PID"
    stop_process "$XCTRACE_PID"
    stop_process "$CURRENT_PID"
    if [[ "$HAD_DEFAULTS" == "1" ]]; then
        defaults import "$DEFAULTS_DOMAIN" "$BACKUP" >/dev/null
    else
        defaults delete "$DEFAULTS_DOMAIN" >/dev/null 2>&1 || true
    fi
    rm -rf "$BACKUP_DIR"
    rm -f "$PROC_METRICS"
}
trap cleanup EXIT INT TERM

defaults import "$DEFAULTS_DOMAIN" "$FIXTURE" >/dev/null

{
    echo "scenario=$SCENARIO"
    echo "fixture=$FIXTURE"
    echo "warmup_seconds=$WARMUP_SECONDS"
    echo "measurement_seconds=$MEASUREMENT_SECONDS"
    echo "app_duration_seconds=$APP_DURATION_SECONDS"
    echo "repetitions=$REPETITIONS"
    echo "trace_backend=$TRACE_BACKEND"
    echo "agent_enabled_override=${N1KO_AGENT_ENABLED:-default}"
    echo "concurrent_n1ko_pids=${EXISTING_N1KO_PIDS:-none}"
    echo "checkout=$(git rev-parse HEAD)"
    echo "macos=$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    echo "hardware=$(sysctl -n hw.model), cpu=$(sysctl -n hw.ncpu), memory=$(sysctl -n hw.memsize)"
    echo "swift=$(swiftc --version 2>&1 | head -1)"
} > "$OUTPUT_ROOT/metadata.txt"

printf 'repetition\tmeasured_seconds\taverage_cpu_percent\tp95_cpu_percent\twakeups_per_second\tstart_physical_footprint_mb\tphysical_footprint_mb\tphysical_footprint_growth_mb\tpeak_footprint_mb\n' > "$OUTPUT_ROOT/summary.tsv"

for repetition in $(seq 1 "$REPETITIONS"); do
    RUN_DIR="$OUTPUT_ROOT/run-$repetition"
    mkdir -p "$RUN_DIR"
    READY_PATH="$RUN_DIR/ready"
    COUNTERS_PATH="$RUN_DIR/performance-counters.json"

    env \
        N1KO_PERF_SCENARIO="$SCENARIO" \
        N1KO_PERF_WARMUP_SECONDS="$WARMUP_SECONDS" \
        N1KO_PERF_DURATION_SECONDS="$APP_DURATION_SECONDS" \
        N1KO_PERF_READY_PATH="$READY_PATH" \
        N1KO_PERF_OUTPUT_PATH="$COUNTERS_PATH" \
        "$APP_EXE" > "$RUN_DIR/stdout.txt" 2> "$RUN_DIR/stderr.txt" &
    CURRENT_PID=$!

    deadline=$((SECONDS + WARMUP_SECONDS + 30))
    while [[ ! -f "$READY_PATH" ]]; do
        kill -0 "$CURRENT_PID" >/dev/null 2>&1 || {
            echo "Benchmark process exited before warm-up completed" >&2
            exit 1
        }
        (( SECONDS < deadline )) || { echo "Timed out waiting for benchmark warm-up" >&2; exit 1; }
        sleep 1
    done

    RUN_PID="$CURRENT_PID"
    LOG_START="$(date '+%Y-%m-%d %H:%M:%S')"
    WALL_START="$(date +%s)"
    "$PROC_METRICS" "$CURRENT_PID" > "$RUN_DIR/rusage-start.json"
    top -l "$MEASUREMENT_SECONDS" -s 1 -pid "$CURRENT_PID" -stats pid,cpu,mem,threads > "$RUN_DIR/top.txt" 2>&1 &
    TOP_PID=$!

    vmmap -summary "$CURRENT_PID" > "$RUN_DIR/vmmap-summary.txt" 2>&1 || true
    sample "$CURRENT_PID" "$SAMPLE_SECONDS" 1 -mayDie -file "$RUN_DIR/time-profile.sample.txt" >/dev/null 2>&1 || true

    if [[ "$TRACE_BACKEND" == xctrace:* ]]; then
        DEVELOPER_DIR="$XCTRACE_DEVELOPER_DIR" xcrun xctrace record \
            --template "$XCTRACE_TEMPLATE" \
            --attach "$CURRENT_PID" \
            --time-limit "${MEASUREMENT_SECONDS}s" \
            --output "$RUN_DIR/${XCTRACE_TEMPLATE// /-}.trace" > "$RUN_DIR/xctrace.txt" 2>&1 &
        XCTRACE_PID=$!
    fi

    elapsed=$(( $(date +%s) - WALL_START ))
    remaining=$(( MEASUREMENT_SECONDS - elapsed - 2 ))
    if (( remaining > 0 )); then sleep "$remaining"; fi
    "$PROC_METRICS" "$CURRENT_PID" > "$RUN_DIR/rusage-end.json"
    WALL_END="$(date +%s)"
    wait "$CURRENT_PID" || true
    CURRENT_PID=""
    kill "$TOP_PID" >/dev/null 2>&1 || true
    wait "$TOP_PID" || true
    TOP_PID=""
    if [[ -n "$XCTRACE_PID" ]]; then
        wait "$XCTRACE_PID" || true
        XCTRACE_PID=""
    fi
    LOG_END="$(date '+%Y-%m-%d %H:%M:%S')"

    scenario_state_valid=$(plutil -extract metadata.scenarioStateValidAtEnd raw -o - "$COUNTERS_PATH")
    if [[ "$scenario_state_valid" != "true" ]]; then
        echo "Benchmark state validation failed for $SCENARIO (scenarioStateValidAtEnd=$scenario_state_valid)" >&2
        exit 1
    fi
    if [[ "$SCENARIO" == "quick-panel-cards" || "$SCENARIO" == "quick-panel-gauges" ]]; then
        panel_updates=$(plutil -extract counters.quickPanelUpdate.count raw -o - "$COUNTERS_PATH" 2>/dev/null || echo 0)
        minimum_panel_updates=$((MEASUREMENT_SECONDS / 4))
        if (( panel_updates < minimum_panel_updates )); then
            echo "Quick Panel closed or stopped updating (updates=$panel_updates, expected-at-least=$minimum_panel_updates)" >&2
            exit 1
        fi
    fi
    if [[ "$SCENARIO" == "panel-settings-100-cycles" ]]; then
        completed_cycles=$(plutil -extract metadata.lifecycleCyclesCompleted raw -o - "$COUNTERS_PATH")
        if [[ "$completed_cycles" != "100" ]]; then
            echo "Lifecycle scenario completed $completed_cycles cycles instead of 100" >&2
            exit 1
        fi
    fi
    if [[ "$SCENARIO" == "agent-surface-hidden" ]]; then
        surface_visible=$(plutil -extract metadata.agentSurfaceVisible raw -o - "$COUNTERS_PATH")
        surface_monitors=$(plutil -extract metadata.agentSurfaceActiveGlobalMonitors raw -o - "$COUNTERS_PATH")
        surface_retries=$(plutil -extract metadata.agentSurfaceActiveRetryTasks raw -o - "$COUNTERS_PATH")
        if [[ "$surface_visible" != "false" || "$surface_monitors" != "0" || "$surface_retries" != "0" ]]; then
            echo "Hidden Agent surface retained presentation resources (visible=$surface_visible monitors=$surface_monitors retries=$surface_retries)" >&2
            exit 1
        fi
    fi

    /usr/bin/log show \
        --start "$LOG_START" \
        --end "$LOG_END" \
        --signpost \
        --style compact \
        --predicate "processIdentifier == $RUN_PID AND subsystem == \"com.n1ko.state.monitor\"" \
        > "$RUN_DIR/signposts.txt" 2> "$RUN_DIR/signposts.stderr.txt" || true

    start_user=$(plutil -extract userTimeNanoseconds raw -o - "$RUN_DIR/rusage-start.json")
    start_system=$(plutil -extract systemTimeNanoseconds raw -o - "$RUN_DIR/rusage-start.json")
    end_user=$(plutil -extract userTimeNanoseconds raw -o - "$RUN_DIR/rusage-end.json")
    end_system=$(plutil -extract systemTimeNanoseconds raw -o - "$RUN_DIR/rusage-end.json")
    start_idle=$(plutil -extract packageIdleWakeups raw -o - "$RUN_DIR/rusage-start.json")
    start_interrupt=$(plutil -extract interruptWakeups raw -o - "$RUN_DIR/rusage-start.json")
    end_idle=$(plutil -extract packageIdleWakeups raw -o - "$RUN_DIR/rusage-end.json")
    end_interrupt=$(plutil -extract interruptWakeups raw -o - "$RUN_DIR/rusage-end.json")
    start_footprint=$(plutil -extract physicalFootprintBytes raw -o - "$RUN_DIR/rusage-start.json")
    footprint=$(plutil -extract physicalFootprintBytes raw -o - "$RUN_DIR/rusage-end.json")
    peak=$(plutil -extract lifetimeMaximumPhysicalFootprintBytes raw -o - "$RUN_DIR/rusage-end.json")

    measured_seconds=$((WALL_END - WALL_START))
    cpu_average=$(awk -v u0="$start_user" -v s0="$start_system" -v u1="$end_user" -v s1="$end_system" -v d="$measured_seconds" 'BEGIN { printf "%.3f", ((u1-u0)+(s1-s0))/1000000000/d*100 }')
    wakeups_per_second=$(awk -v a0="$start_idle" -v b0="$start_interrupt" -v a1="$end_idle" -v b1="$end_interrupt" -v d="$measured_seconds" 'BEGIN { printf "%.3f", ((a1-a0)+(b1-b0))/d }')
    start_footprint_mb=$(awk -v bytes="$start_footprint" 'BEGIN { printf "%.2f", bytes/1048576 }')
    footprint_mb=$(awk -v bytes="$footprint" 'BEGIN { printf "%.2f", bytes/1048576 }')
    footprint_growth_mb=$(awk -v start="$start_footprint" -v finish="$footprint" 'BEGIN { printf "%.2f", (finish-start)/1048576 }')
    peak_mb=$(awk -v bytes="$peak" 'BEGIN { printf "%.2f", bytes/1048576 }')
    awk '$1 ~ /^[0-9]+$/ { gsub(/%/, "", $2); print $2 }' "$RUN_DIR/top.txt" | sort -n > "$RUN_DIR/cpu-samples.txt"
    p95_cpu=$(awk '{ values[NR]=$1 } END { if (NR == 0) { print "n/a" } else { idx=int((NR*95+99)/100); if (idx < 1) idx=1; if (idx > NR) idx=NR; printf "%.3f", values[idx] } }' "$RUN_DIR/cpu-samples.txt")

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$repetition" "$measured_seconds" "$cpu_average" "$p95_cpu" "$wakeups_per_second" "$start_footprint_mb" "$footprint_mb" "$footprint_growth_mb" "$peak_mb" >> "$OUTPUT_ROOT/summary.tsv"
done

echo "Benchmark evidence: $OUTPUT_ROOT"
