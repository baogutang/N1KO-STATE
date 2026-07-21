#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "usage: analyze_wp6_soak.sh <monitoring-only|agent-enabled> <external.tsv> <internal.tsv> <expected-seconds> <summary.txt>" >&2
    exit 64
fi

SCENARIO="$1"
EXTERNAL="$2"
INTERNAL="$3"
EXPECTED_SECONDS="$4"
SUMMARY="$5"

case "$SCENARIO" in
    monitoring-only)
        CPU_BUDGET="0.50"
        POWER_BUDGET_MW="150"
        EXPECTED_SESSIONS="0"
        ;;
    agent-enabled)
        CPU_BUDGET="0.65"
        POWER_BUDGET_MW="175"
        EXPECTED_SESSIONS="200"
        ;;
    *) echo "unknown WP6 soak scenario: $SCENARIO" >&2; exit 64 ;;
esac
[[ "$EXPECTED_SECONDS" =~ ^[0-9]+$ ]] || { echo "expected seconds must be an integer" >&2; exit 64; }
[[ -s "$EXTERNAL" && -s "$INTERNAL" ]] || { echo "soak samples are missing" >&2; exit 66; }

WAKEUPS_BUDGET="5.0"
FOOTPRINT_GROWTH_BUDGET_MB="8.0"
FOOTPRINT_SLOPE_BUDGET_MB_H="0.50"
THREAD_GROWTH_BUDGET="2"
FD_GROWTH_BUDGET="3"
SOCKET_GROWTH_BUDGET="0"

external_metrics="$({
    awk -F '\t' '
        NR == 1 { next }
        NR == 2 {
            firstElapsed=$2; firstCPU=$3+$4; firstWake=$6+$7;
            firstFootprint=$9; firstThreads=$11; firstFDs=$12; firstSockets=$13;
            firstEnergy=$14
        }
        NR > 1 {
            count++;
            lastElapsed=$2; lastCPU=$3+$4; lastWake=$6+$7;
            lastFootprint=$9; lastThreads=$11; lastFDs=$12; lastSockets=$13;
            lastEnergy=$14;
            x=$2; y=$9; sx+=x; sy+=y; sxx+=x*x; sxy+=x*y
        }
        END {
            duration=lastElapsed-firstElapsed;
            if (count < 2 || duration <= 0) exit 2;
            averageCPU=(lastCPU-firstCPU)/duration/10000000;
            wakeups=(lastWake-firstWake)/duration;
            averagePowerMW=(lastEnergy-firstEnergy)/duration/1000000;
            energySupported=lastEnergy > firstEnergy ? "true" : "false";
            growthMB=(lastFootprint-firstFootprint)/1048576;
            denominator=count*sxx-sx*sx;
            slopeBytesSecond=denominator == 0 ? 0 : (count*sxy-sx*sy)/denominator;
            slopeMBHour=slopeBytesSecond*3600/1048576;
            printf "sample_count=%d\n", count;
            printf "elapsed_seconds=%.3f\n", lastElapsed;
            printf "average_cpu_percent=%.6f\n", averageCPU;
            printf "cpu_time_delta_ns=%.0f\n", lastCPU-firstCPU;
            printf "wakeups_per_second=%.6f\n", wakeups;
            printf "wakeup_delta=%.0f\n", lastWake-firstWake;
            printf "average_power_mw=%.6f\n", averagePowerMW;
            printf "energy_delta_nj=%.0f\n", lastEnergy-firstEnergy;
            printf "energy_counter_supported=%s\n", energySupported;
            printf "footprint_growth_mb=%.6f\n", growthMB;
            printf "footprint_slope_mb_per_hour=%.6f\n", slopeMBHour;
            printf "thread_growth=%d\n", lastThreads-firstThreads;
            printf "fd_growth=%d\n", lastFDs-firstFDs;
            printf "socket_growth=%d\n", lastSockets-firstSockets;
        }
    ' "$EXTERNAL"
} 2>/dev/null)" || { echo "not enough external soak samples" >&2; exit 65; }

internal_metrics="$(awk -F '\t' '
    NR == 1 { next }
    NR == 2 {
        firstWall=$1; firstUptime=$2;
        firstSessions=$7; firstSockets=$8; firstWatchers=$9; firstTransports=$10;
        firstTasks=$11; firstActiveTasks=$12; firstProcesses=$13; firstActiveProcesses=$14;
        firstRoutes=$15; firstObservers=$16; firstMonitors=$17; firstRetries=$18;
        minHistory=$3; maxHistory=$3
    }
    NR > 1 {
        lastWall=$1; lastUptime=$2;
        count++; lastSessions=$7; lastSockets=$8; lastWatchers=$9; lastTransports=$10;
        lastTasks=$11; lastActiveTasks=$12; lastProcesses=$13; lastActiveProcesses=$14;
        lastRoutes=$15; lastObservers=$16; lastMonitors=$17; lastRetries=$18;
        sleepEvents=$19; wakeEvents=$20; sessionInactiveEvents=$21; sessionActiveEvents=$22;
        screenSleepEvents=$23; screenWakeEvents=$24;
        if ($3 < minHistory) minHistory=$3; if ($3 > maxHistory) maxHistory=$3;
        if ($3 > 2880 || $4 > 2880 || $5 > 2880 || $6 > 2880) historyOverflow=1;
        if (NR > 2 && ($3 < previousHistory || $4 < previousMemory || $5 < previousDown || $6 < previousUp)) historyRegressed=1;
        previousHistory=$3; previousMemory=$4; previousDown=$5; previousUp=$6
    }
    END {
        if (count < 2) exit 2;
        printf "internal_sample_count=%d\n", count;
        printf "internal_wall_elapsed_seconds=%.3f\n", lastWall-firstWall;
        printf "monotonic_awake_elapsed_seconds=%.3f\n", (lastUptime-firstUptime)/1000000000;
        printf "inferred_sleep_seconds=%.3f\n", (lastWall-firstWall)-(lastUptime-firstUptime)/1000000000;
        printf "agent_session_first=%d\n", firstSessions;
        printf "agent_session_last=%d\n", lastSessions;
        printf "agent_socket_growth=%d\n", lastSockets-firstSockets;
        printf "agent_watcher_growth=%d\n", lastWatchers-firstWatchers;
        printf "agent_transport_growth=%d\n", lastTransports-firstTransports;
        printf "agent_registered_task_growth=%d\n", lastTasks-firstTasks;
        printf "agent_active_task_growth=%d\n", lastActiveTasks-firstActiveTasks;
        printf "agent_registered_subprocess_growth=%d\n", lastProcesses-firstProcesses;
        printf "agent_active_subprocess_growth=%d\n", lastActiveProcesses-firstActiveProcesses;
        printf "agent_pending_route_growth=%d\n", lastRoutes-firstRoutes;
        printf "agent_snapshot_observer_growth=%d\n", lastObservers-firstObservers;
        printf "surface_monitor_growth=%d\n", lastMonitors-firstMonitors;
        printf "surface_retry_growth=%d\n", lastRetries-firstRetries;
        printf "history_first_count=%d\n", minHistory;
        printf "history_last_count=%d\n", maxHistory;
        printf "history_overflow=%d\n", historyOverflow ? 1 : 0;
        printf "history_regressed=%d\n", historyRegressed ? 1 : 0;
        printf "system_sleep_events=%d\n", sleepEvents;
        printf "system_wake_events=%d\n", wakeEvents;
        printf "session_inactive_events=%d\n", sessionInactiveEvents;
        printf "session_active_events=%d\n", sessionActiveEvents;
        printf "screen_sleep_events=%d\n", screenSleepEvents;
        printf "screen_wake_events=%d\n", screenWakeEvents;
    }
' "$INTERNAL")" || { echo "not enough internal soak samples" >&2; exit 65; }

metric() {
    local key="$1"
    printf '%s\n%s\n' "$external_metrics" "$internal_metrics" | awk -F= -v key="$key" '$1 == key { print $2; exit }'
}

elapsed="$(metric elapsed_seconds)"
awake_elapsed="$(metric monotonic_awake_elapsed_seconds)"
wall_average_cpu="$(metric average_cpu_percent)"
wall_average_power="$(metric average_power_mw)"
wall_wakeups="$(metric wakeups_per_second)"
average_cpu="$(awk -v delta="$(metric cpu_time_delta_ns)" -v seconds="$awake_elapsed" 'BEGIN { printf "%.6f", delta/seconds/10000000 }')"
average_power="$(awk -v delta="$(metric energy_delta_nj)" -v seconds="$awake_elapsed" 'BEGIN { printf "%.6f", delta/seconds/1000000 }')"
wakeups="$(awk -v delta="$(metric wakeup_delta)" -v seconds="$awake_elapsed" 'BEGIN { printf "%.6f", delta/seconds }')"
footprint_growth="$(metric footprint_growth_mb)"
footprint_slope="$(metric footprint_slope_mb_per_hour)"
thread_growth="$(metric thread_growth)"
fd_growth="$(metric fd_growth)"
socket_growth="$(metric socket_growth)"
session_first="$(metric agent_session_first)"
session_last="$(metric agent_session_last)"

p95_cpu="$(tail -n +3 "$EXTERNAL" | cut -f5 | sort -n | awk '
    { values[NR]=$1 }
    END { if (NR == 0) print "0"; else { rank=int((NR*95+99)/100); print values[rank] } }
')"

evidence_class="calibration"
duration_complete="true"
if (( EXPECTED_SECONDS >= 86400 )); then
    evidence_class="release-soak"
    duration_complete="$(awk -v actual="$awake_elapsed" -v expected="$EXPECTED_SECONDS" 'BEGIN { print actual + 120 >= expected ? "true" : "false" }')"
fi

failures=()
check_max_float() {
    local label="$1" value="$2" budget="$3"
    if ! awk -v value="$value" -v budget="$budget" 'BEGIN { exit(value <= budget ? 0 : 1) }'; then
        failures+=("$label=$value exceeds $budget")
    fi
}
check_max_int() {
    local label="$1" value="$2" budget="$3"
    (( value <= budget )) || failures+=("$label=$value exceeds $budget")
}
check_zero_growth() {
    local key="$1" value
    value="$(metric "$key")"
    (( value == 0 )) || failures+=("$key=$value expected 0")
}

check_max_float average_cpu_percent "$average_cpu" "$CPU_BUDGET"
check_max_float average_power_mw "$average_power" "$POWER_BUDGET_MW"
check_max_float wakeups_per_second "$wakeups" "$WAKEUPS_BUDGET"
check_max_float footprint_growth_mb "$footprint_growth" "$FOOTPRINT_GROWTH_BUDGET_MB"
if [[ "$evidence_class" == "release-soak" ]]; then
    check_max_float footprint_slope_mb_per_hour "$footprint_slope" "$FOOTPRINT_SLOPE_BUDGET_MB_H"
fi
check_max_int thread_growth "$thread_growth" "$THREAD_GROWTH_BUDGET"
check_max_int fd_growth "$fd_growth" "$FD_GROWTH_BUDGET"
check_max_int socket_growth "$socket_growth" "$SOCKET_GROWTH_BUDGET"
for key in agent_socket_growth agent_watcher_growth agent_transport_growth \
    agent_registered_task_growth agent_active_task_growth agent_registered_subprocess_growth \
    agent_active_subprocess_growth agent_pending_route_growth agent_snapshot_observer_growth \
    surface_monitor_growth surface_retry_growth; do
    check_zero_growth "$key"
done
[[ "$(metric history_overflow)" == "0" ]] || failures+=("history exceeded 2880 samples")
[[ "$(metric history_regressed)" == "0" ]] || failures+=("history count regressed before reaching capacity")
[[ "$(metric energy_counter_supported)" == "true" ]] || failures+=("cumulative energy counter unavailable")
if (( $(metric system_wake_events) < $(metric system_sleep_events) )); then
    failures+=("system lifecycle ended with an unmatched sleep event")
fi
if (( $(metric session_active_events) < $(metric session_inactive_events) )); then
    failures+=("user-session lifecycle ended inactive")
fi
if [[ "$session_first" != "$EXPECTED_SESSIONS" || "$session_last" != "$EXPECTED_SESSIONS" ]]; then
    failures+=("agent sessions changed or fixture missing: first=$session_first last=$session_last expected=$EXPECTED_SESSIONS")
fi
[[ "$duration_complete" == "true" ]] || failures+=("24-hour awake duration incomplete: actual=$awake_elapsed expected=$EXPECTED_SECONDS")

status="CALIBRATION_PASS"
if [[ "$evidence_class" == "release-soak" ]]; then status="RELEASE_PASS"; fi
if (( ${#failures[@]} > 0 )); then
    status="FAIL"
fi

mkdir -p "$(dirname "$SUMMARY")"
{
    echo "status=$status"
    echo "evidence_class=$evidence_class"
    echo "scenario=$SCENARIO"
    echo "expected_seconds=$EXPECTED_SECONDS"
    echo "duration_complete=$duration_complete"
    echo "$external_metrics"
    echo "awake_average_cpu_percent=$average_cpu"
    echo "awake_average_power_mw=$average_power"
    echo "awake_wakeups_per_second=$wakeups"
    echo "wall_average_cpu_percent=$wall_average_cpu"
    echo "wall_average_power_mw=$wall_average_power"
    echo "wall_wakeups_per_second=$wall_wakeups"
    echo "p95_cpu_percent=$p95_cpu"
    echo "$internal_metrics"
    echo "budget_average_cpu_percent=$CPU_BUDGET"
    echo "budget_average_power_mw=$POWER_BUDGET_MW"
    echo "budget_wakeups_per_second=$WAKEUPS_BUDGET"
    echo "budget_footprint_growth_mb=$FOOTPRINT_GROWTH_BUDGET_MB"
    echo "budget_footprint_slope_mb_per_hour=$FOOTPRINT_SLOPE_BUDGET_MB_H"
    echo "footprint_slope_gate_applied=$([[ "$evidence_class" == "release-soak" ]] && echo true || echo false)"
    echo "budget_thread_growth=$THREAD_GROWTH_BUDGET"
    echo "budget_fd_growth=$FD_GROWTH_BUDGET"
    echo "budget_socket_growth=$SOCKET_GROWTH_BUDGET"
    if (( ${#failures[@]} == 0 )); then
        echo "failures=none"
    else
        printf 'failure=%s\n' "${failures[@]}"
    fi
} > "$SUMMARY"

cat "$SUMMARY"
(( ${#failures[@]} == 0 ))
