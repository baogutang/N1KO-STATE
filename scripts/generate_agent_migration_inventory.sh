#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UPSTREAM_URL="https://github.com/erha19/ping-island.git"
UPSTREAM_COMMIT="da130d679e830894240e926184d29751dfd2def1"
OUTPUT="${1:-$ROOT/docs/roadmap/wp0-upstream-file-inventory.tsv}"
WORK="$(mktemp -d -t n1ko-agent-inventory)"
trap 'rm -rf "$WORK"' EXIT

git clone --filter=blob:none --no-checkout "$UPSTREAM_URL" "$WORK/repo" >/dev/null
git -C "$WORK/repo" fetch --depth 1 origin "$UPSTREAM_COMMIT" >/dev/null

classify() {
    local path="$1"
    case "$path" in
        LICENSE.md|NOTICE)
            echo "reuse"
            ;;
        PingIsland/App/*|PingIsland/UI/*|PingIsland/Core/IslandPresentation.swift|PingIsland/Core/NotchActivityCoordinator.swift|PingIsland/Core/NotchGeometry.swift|PingIsland/Core/NotchViewModel.swift|PingIsland/Core/ScreenNotchMetrics.swift|PingIsland/Core/ScreenSelector.swift|PingIsland/Core/Settings.swift|PingIsland/Core/SoundPackCatalog.swift|PingIsland/Core/SoundSelector.swift|PingIsland/Utilities/FullscreenAppDetector.swift|PingIsland/Info*.plist|PingIsland/Resources/*.entitlements|PingIsland/Resources/*.lproj/*|PingIslandUITests/*)
            echo "rewrite"
            ;;
        PingIsland/Models/ChatMessage.swift|PingIsland/Models/SessionEvent.swift|PingIsland/Models/SessionPhase.swift|PingIsland/Models/SessionProvider.swift|PingIsland/Models/SessionState.swift|PingIsland/Models/ToolResultData.swift|PingIsland/Services/Codex/CodexRolloutParser.swift|PingIsland/Services/Codex/CodexThreadSnapshot.swift|PingIsland/Services/Session/ConversationParser.swift|PingIsland/Services/State/SessionAssociationStore.swift|PingIsland/Services/State/ToolEventProcessor.swift|PingIsland/Services/Usage/AgentUsageAnalytics.swift|PingIsland/Services/Usage/ClaudeTranscriptUsage.swift|PingIsland/Services/Usage/ClaudeUsage.swift|PingIsland/Services/Usage/CodexUsage.swift|PingIsland/Services/Usage/UsageSummaryPresenter.swift|PingIsland/Utilities/MCPToolFormatter.swift|PingIsland/Utilities/SessionPhaseHelpers.swift|PingIsland/Utilities/SessionTextSanitizer.swift)
            echo "reuse"
            ;;
        PingIsland/Events/*|PingIsland/Models/ClientProfile.swift|PingIsland/Core/EnergyGovernor.swift|PingIsland/Core/FeatureFlags.swift|PingIsland/Core/UserIdleAutoProtection.swift|PingIsland/Services/Chat/*|PingIsland/Services/Codex/CodexAppServerMonitor.swift|PingIsland/Services/Hooks/*|PingIsland/Services/Runtime/*|PingIsland/Services/Session/*|PingIsland/Services/Shared/*|PingIsland/Services/State/*|PingIsland/Services/Usage/UsageSnapshotCacheStore.swift|PingIsland/Utilities/ActiveWindowFrameResolver.swift|PingIsland/Utilities/GlobalShortcut.swift|PingIsland/Utilities/SessionAttentionSoundEvaluator.swift)
            echo "adapt-behind-protocol"
            ;;
        PingIslandTests/Claude*|PingIslandTests/Codex*|PingIslandTests/NativeRuntime*|PingIslandTests/RuntimeSessionRegistryTests.swift|PingIslandTests/Session*|PingIslandTests/Usage*|PingIslandTests/AgentUsageAnalyticsTests.swift|PingIslandTests/ClientProfileIconTests.swift|PingIslandTests/ProcessTreeBuilderTests.swift|PingIslandTests/RecentInterventionResponseStoreTests.swift)
            echo "adapt-behind-protocol"
            ;;
        PingIslandTests/ActiveWindowFrameResolverTests.swift|PingIslandTests/EnergyGovernorTests.swift|PingIslandTests/FeatureFlagsTests.swift|PingIslandTests/GlobalShortcutTests.swift)
            echo "adapt-behind-protocol"
            ;;
        PingIslandTests/*)
            echo "exclude-until-parity"
            ;;
        PingIsland/Assets.xcassets/*|PingIsland/Resources/Fonts/*|PingIsland/Resources/Sounds/*|docs/images/*)
            echo "exclude-until-parity"
            ;;
        PingIsland/Models/MascotStatus.swift|PingIsland/Models/TmuxTarget.swift|PingIsland/Services/Remote/*|PingIsland/Services/Tmux/*|PingIsland/Services/Window/*|PingIsland/Utilities/TerminalVisibilityDetector.swift|PingIsland/Services/Update/*)
            echo "exclude-until-parity"
            ;;
        *)
            echo "exclude-until-parity"
            ;;
    esac
}

license_for() {
    local path="$1"
    case "$path" in
        PingIsland/Resources/Fonts/Silkscreen-Bold.ttf|PingIsland/Resources/Fonts/Silkscreen-OFL.txt)
            echo "OFL-1.1"
            ;;
        PingIsland/Assets.xcassets/*|PingIsland/Resources/Sounds/*|docs/images/*)
            echo "asset-rights-unproven"
            ;;
        LICENSE.md|NOTICE)
            echo "legal-attribution"
            ;;
        *)
            echo "Apache-2.0"
            ;;
    esac
}

note_for() {
    local path="$1"
    local disposition="$2"
    case "$path" in
        LICENSE.md|NOTICE)
            echo "retain in third-party notices; upstream name is legal attribution only"
            ;;
        PingIsland/Resources/Fonts/*)
            echo "do not bundle in first slice; OFL text is present but N1KO UI uses system typography"
            ;;
        PingIsland/Assets.xcassets/*|PingIsland/Resources/Sounds/*|docs/images/*)
            echo "do not migrate without per-asset provenance; replace with N1KO-owned resources if needed"
            ;;
        PingIsland/App/*|PingIsland/UI/*|PingIsland/Services/Update/*)
            echo "second app lifecycle/presentation/updater is forbidden; N1KO owns replacement"
            ;;
        *)
            case "$disposition" in
                reuse) echo "selected logic may be copied with Apache notice and prominent modification marker" ;;
                adapt-behind-protocol) echo "port behavior behind N1KO-owned protocol; rename paths and remove singleton/product coupling" ;;
                rewrite) echo "reimplement in N1KO architecture and product identity; do not copy application shell" ;;
                exclude-until-parity) echo "not in first Claude+Codex core slice; reconsider only in its dependency-satisfied parity package" ;;
            esac
            ;;
    esac
}

mkdir -p "$(dirname "$OUTPUT")"
{
    printf '# upstream\t%s\n' "$UPSTREAM_URL"
    printf '# commit\t%s\n' "$UPSTREAM_COMMIT"
    printf 'path\tdisposition\tlicense\townership_and_action\n'
    while IFS= read -r path; do
        disposition="$(classify "$path")"
        license="$(license_for "$path")"
        note="$(note_for "$path" "$disposition")"
        printf '%s\t%s\t%s\t%s\n' "$path" "$disposition" "$license" "$note"
    done < <(git -C "$WORK/repo" ls-tree -r --name-only FETCH_HEAD)
} > "$OUTPUT"

count=$(git -C "$WORK/repo" ls-tree -r --name-only FETCH_HEAD | wc -l | tr -d ' ')
echo "Migration inventory: $OUTPUT ($count files)"
