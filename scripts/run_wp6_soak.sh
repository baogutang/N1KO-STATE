#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCENARIO="${1:-}"
case "$SCENARIO" in
    monitoring-only)
        PERF_SCENARIO="menu-bar-only"
        AGENT_ENABLED="0"
        SEED_SESSIONS="0"
        ;;
    agent-enabled)
        PERF_SCENARIO="agent-core-idle"
        AGENT_ENABLED="1"
        SEED_SESSIONS="${SEED_SESSIONS:-200}"
        ;;
    *)
        echo "usage: $0 <monitoring-only|agent-enabled>" >&2
        exit 64
        ;;
esac

DURATION_SECONDS="${DURATION_SECONDS:-86400}"
WARMUP_SECONDS="${WARMUP_SECONDS:-120}"
SAMPLE_INTERVAL_SECONDS="${SAMPLE_INTERVAL_SECONDS:-60}"
SKIP_BUILD="${SKIP_BUILD:-0}"
ALLOW_CONCURRENT_N1KO="${ALLOW_CONCURRENT_N1KO:-0}"
BUILD_DEVELOPER_DIR="${BUILD_DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT/docs/roadmap/evidence/wp6/$(date +%Y-%m-%d)/soaks/$SCENARIO/$STAMP}"

for value in "$DURATION_SECONDS" "$WARMUP_SECONDS" "$SAMPLE_INTERVAL_SECONDS" "$SEED_SESSIONS"; do
    [[ "$value" =~ ^[0-9]+$ ]] || { echo "durations and seed count must be integers" >&2; exit 64; }
done
(( DURATION_SECONDS > 0 && SAMPLE_INTERVAL_SECONDS > 0 )) || { echo "duration and interval must be positive" >&2; exit 64; }
if (( DURATION_SECONDS < 86400 )); then
    EVIDENCE_CLASS="calibration"
else
    EVIDENCE_CLASS="release-soak"
fi

mkdir -p "$OUTPUT_ROOT"
chmod 700 "$OUTPUT_ROOT"
echo "running" > "$OUTPUT_ROOT/status.txt"
echo "$$" > "$OUTPUT_ROOT/runner.pid"

if [[ "$SKIP_BUILD" != "1" ]]; then
    DEVELOPER_DIR="$BUILD_DEVELOPER_DIR" ./build_app.sh --native
fi

APP_EXE="$ROOT/build/N1KO-STATE.app/Contents/MacOS/N1KOState"
BRIDGE_EXE="$ROOT/build/N1KO-STATE.app/Contents/MacOS/n1ko-agent-bridge"
[[ -x "$APP_EXE" ]] || { echo "native app executable is missing" >&2; exit 66; }
if [[ "$AGENT_ENABLED" == "1" && ! -x "$BRIDGE_EXE" ]]; then
    echo "native Agent bridge is missing" >&2
    exit 66
fi

EXISTING_N1KO_PIDS="$(pgrep -x N1KOState | tr '\n' ',' | sed 's/,$//' || true)"
if [[ -n "$EXISTING_N1KO_PIDS" && "$ALLOW_CONCURRENT_N1KO" != "1" ]]; then
    echo "N1KOState is already running (pid(s): $EXISTING_N1KO_PIDS); quit it before an isolated soak" >&2
    exit 73
fi

PROC_METRICS="$(mktemp -t n1ko-wp6-proc-metrics)"
DEVELOPER_DIR="$BUILD_DEVELOPER_DIR" xcrun clang -O2 "$ROOT/scripts/performance/proc_metrics.c" -o "$PROC_METRICS"
RUNTIME_DIR="$(mktemp -d -t n1ko-wp6-runtime)"
SUPPORT_DIR="$OUTPUT_ROOT/isolated/AgentCore"
ROLLOUT_DIR="$OUTPUT_ROOT/isolated/codex-sessions"
HISTORY_PATH="$OUTPUT_ROOT/isolated/history.json"
mkdir -p "$SUPPORT_DIR" "$ROLLOUT_DIR"
chmod 700 "$SUPPORT_DIR" "$ROLLOUT_DIR"

DEFAULTS_DOMAIN="com.n1ko.state.monitor"
PREFERENCES_HOME="$OUTPUT_ROOT/isolated/preferences-home"
mkdir -p "$PREFERENCES_HOME/Library/Preferences"
chmod 700 "$PREFERENCES_HOME" "$PREFERENCES_HOME/Library" "$PREFERENCES_HOME/Library/Preferences"
CFFIXED_USER_HOME="$PREFERENCES_HOME" defaults import \
    "$DEFAULTS_DOMAIN" "$ROOT/Fixtures/Performance/baseline-all-modules-2s.plist" >/dev/null

CURRENT_PID=""
INTERRUPTED=0

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
    stop_process "$CURRENT_PID"
    rm -rf "$RUNTIME_DIR"
    rm -f "$PROC_METRICS"
}

interrupt() {
    INTERRUPTED=1
    echo "interrupted; partial evidence retained" > "$OUTPUT_ROOT/status.txt"
    exit 130
}
trap cleanup EXIT
trap interrupt INT TERM

{
    echo "status=running"
    echo "evidence_class=$EVIDENCE_CLASS"
    echo "scenario=$SCENARIO"
    echo "performance_scenario=$PERF_SCENARIO"
    echo "agent_enabled=$AGENT_ENABLED"
    echo "synthetic_session_seed=$SEED_SESSIONS"
    echo "warmup_seconds=$WARMUP_SECONDS"
    echo "duration_seconds=$DURATION_SECONDS"
    echo "sample_interval_seconds=$SAMPLE_INTERVAL_SECONDS"
    echo "history_path=isolated/history.json"
    echo "preferences_home=isolated/preferences-home"
    echo "agent_support=isolated/AgentCore"
    echo "codex_rollouts=isolated/codex-sessions"
    echo "checkout=$(git rev-parse HEAD)"
    echo "branch=$(git branch --show-current)"
    echo "macos=$(sw_vers -productVersion) ($(sw_vers -buildVersion))"
    echo "hardware=$(sysctl -n hw.model), cpu=$(sysctl -n hw.ncpu), memory=$(sysctl -n hw.memsize)"
    echo "started_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUTPUT_ROOT/metadata.txt"

READY_PATH="$OUTPUT_ROOT/ready"
COUNTERS_PATH="$OUTPUT_ROOT/performance-counters.json"
INTERNAL_SAMPLES="$OUTPUT_ROOT/internal-resources.tsv"
EXTERNAL_SAMPLES="$OUTPUT_ROOT/process-resources.tsv"

env \
    CFFIXED_USER_HOME="$PREFERENCES_HOME" \
    N1KO_AGENT_ENABLED="$AGENT_ENABLED" \
    N1KO_AGENT_RUNTIME_DIRECTORY="$RUNTIME_DIR" \
    N1KO_AGENT_SUPPORT_DIRECTORY="$SUPPORT_DIR" \
    N1KO_CODEX_ROLLOUT_DIRECTORY="$ROLLOUT_DIR" \
    N1KO_HISTORY_PATH="$HISTORY_PATH" \
    N1KO_PERF_SCENARIO="$PERF_SCENARIO" \
    N1KO_PERF_HEADLESS="1" \
    N1KO_PERF_WARMUP_SECONDS="$WARMUP_SECONDS" \
    N1KO_PERF_DURATION_SECONDS="$DURATION_SECONDS" \
    N1KO_PERF_READY_PATH="$READY_PATH" \
    N1KO_PERF_OUTPUT_PATH="$COUNTERS_PATH" \
    N1KO_SOAK_SAMPLES_PATH="$INTERNAL_SAMPLES" \
    N1KO_SOAK_SAMPLE_SECONDS="$SAMPLE_INTERVAL_SECONDS" \
    "$APP_EXE" > "$OUTPUT_ROOT/stdout.txt" 2> "$OUTPUT_ROOT/stderr.txt" &
CURRENT_PID=$!
echo "$CURRENT_PID" > "$OUTPUT_ROOT/app.pid"

if (( SEED_SESSIONS > 0 )); then
    deadline=$((SECONDS + 30))
    while [[ ! -S "$RUNTIME_DIR/agent.sock" || ! -f "$RUNTIME_DIR/auth.secret" ]]; do
        kill -0 "$CURRENT_PID" >/dev/null 2>&1 || { echo "app exited before Agent socket became ready" >&2; exit 1; }
        (( SECONDS < deadline )) || { echo "timed out waiting for Agent socket" >&2; exit 1; }
        sleep 0.1
    done
    : > "$OUTPUT_ROOT/synthetic-seed-responses.txt"
    for index in $(seq 1 "$SEED_SESSIONS"); do
        printf '{"session_id":"wp6-soak-%03d","hook_event_name":"SessionStart","cwd":"/tmp/n1ko-wp6-fixture"}' "$index" | \
            "$BRIDGE_EXE" --provider claude --runtime-directory "$RUNTIME_DIR" --event SessionStart \
            >> "$OUTPUT_ROOT/synthetic-seed-responses.txt"
    done
fi

deadline=$((SECONDS + WARMUP_SECONDS + 60))
while [[ ! -f "$READY_PATH" ]]; do
    kill -0 "$CURRENT_PID" >/dev/null 2>&1 || { echo "app exited before soak warm-up completed" >&2; exit 1; }
    (( SECONDS < deadline )) || { echo "timed out waiting for soak warm-up" >&2; exit 1; }
    sleep 1
done

printf 'wall_epoch_seconds\telapsed_seconds\tuser_time_ns\tsystem_time_ns\tinterval_cpu_percent\tpackage_idle_wakeups\tinterrupt_wakeups\tresident_bytes\tphysical_footprint_bytes\tpeak_footprint_bytes\tthread_count\tfd_count\tsocket_count\tenergy_nanojoules\n' > "$EXTERNAL_SAMPLES"
chmod 600 "$EXTERNAL_SAMPLES"
START_EPOCH="$(date +%s)"
PREVIOUS_EPOCH=""
PREVIOUS_CPU=""

json_value() {
    /usr/bin/plutil -extract "$1" raw -o - "$2"
}

while kill -0 "$CURRENT_PID" >/dev/null 2>&1; do
    NOW_EPOCH="$(date +%s)"
    ELAPSED=$((NOW_EPOCH - START_EPOCH))
    SAMPLE_JSON="$OUTPUT_ROOT/.process-sample.json"
    if "$PROC_METRICS" "$CURRENT_PID" > "$SAMPLE_JSON" 2>/dev/null; then
        USER_NS="$(json_value userTimeNanoseconds "$SAMPLE_JSON")"
        SYSTEM_NS="$(json_value systemTimeNanoseconds "$SAMPLE_JSON")"
        TOTAL_CPU=$((USER_NS + SYSTEM_NS))
        CPU_PERCENT="0"
        if [[ -n "$PREVIOUS_EPOCH" && "$NOW_EPOCH" -gt "$PREVIOUS_EPOCH" ]]; then
            CPU_PERCENT="$(awk -v current="$TOTAL_CPU" -v previous="$PREVIOUS_CPU" -v seconds="$((NOW_EPOCH - PREVIOUS_EPOCH))" 'BEGIN { printf "%.6f", (current-previous)/seconds/10000000 }')"
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$NOW_EPOCH" "$ELAPSED" "$USER_NS" "$SYSTEM_NS" "$CPU_PERCENT" \
            "$(json_value packageIdleWakeups "$SAMPLE_JSON")" \
            "$(json_value interruptWakeups "$SAMPLE_JSON")" \
            "$(json_value residentBytes "$SAMPLE_JSON")" \
            "$(json_value physicalFootprintBytes "$SAMPLE_JSON")" \
            "$(json_value lifetimeMaximumPhysicalFootprintBytes "$SAMPLE_JSON")" \
            "$(json_value threadCount "$SAMPLE_JSON")" \
            "$(json_value fileDescriptorCount "$SAMPLE_JSON")" \
            "$(json_value socketDescriptorCount "$SAMPLE_JSON")" \
            "$(json_value energyNanojoules "$SAMPLE_JSON")" >> "$EXTERNAL_SAMPLES"
        PREVIOUS_EPOCH="$NOW_EPOCH"
        PREVIOUS_CPU="$TOTAL_CPU"
    fi
    sleep "$SAMPLE_INTERVAL_SECONDS" &
    wait $! || true
done

set +e
wait "$CURRENT_PID"
APP_STATUS=$?
set -e
CURRENT_PID=""
rm -f "$OUTPUT_ROOT/.process-sample.json"
echo "app_exit_status=$APP_STATUS" >> "$OUTPUT_ROOT/metadata.txt"
echo "finished_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$OUTPUT_ROOT/metadata.txt"
(( APP_STATUS == 0 )) || { echo "app exited with status $APP_STATUS" >&2; exit "$APP_STATUS"; }
[[ -s "$COUNTERS_PATH" ]] || { echo "app did not write final performance counters" >&2; exit 1; }

"$ROOT/scripts/analyze_wp6_soak.sh" \
    "$SCENARIO" "$EXTERNAL_SAMPLES" "$INTERNAL_SAMPLES" "$DURATION_SECONDS" "$OUTPUT_ROOT/summary.txt"

SUMMARY_STATUS="$(awk -F= '$1 == "status" { print $2; exit }' "$OUTPUT_ROOT/summary.txt")"
echo "$SUMMARY_STATUS" > "$OUTPUT_ROOT/status.txt"
echo "status=$SUMMARY_STATUS" >> "$OUTPUT_ROOT/metadata.txt"
echo "WP6 $SCENARIO $EVIDENCE_CLASS finished: $SUMMARY_STATUS"
