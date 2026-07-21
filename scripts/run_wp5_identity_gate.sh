#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

pattern='ping[ _-]?island|com\.wudanwu|PingIslandBridge|\.ping-island'
violations=0

while IFS=: read -r file line content; do
    case "$file" in
        Sources/N1KOAgentCore/AgentLegacyImport.swift|\
        Sources/N1KOAgentCore/AgentManagedHooks.swift|\
        THIRD_PARTY_NOTICES.md|\
        ThirdPartyLicenses/Ping-Island-Apache-2.0.txt|\
        ThirdPartyLicenses/Ping-Island-NOTICE.txt)
            # Exact legacy migration and legally required notice allowlist.
            ;;
        Sources/N1KOAgentCore/AgentEvents.swift|\
        Sources/N1KOAgentCore/AgentModels.swift|\
        Sources/N1KOAgentCore/AgentParsers.swift|\
        Sources/N1KOAgentCore/AgentSessionStore.swift|\
        Sources/N1KOAgentCore/AgentCapabilities.swift|\
        Sources/N1KOState/App/AgentSoundPackController.swift|\
        Sources/N1KOState/App/AgentSurfaceCoordinator.swift|\
        Sources/N1KOState/Views/Agent/AgentIslandDesign.swift|\
        Sources/N1KOState/Views/Agent/AgentMascotView.swift|\
        Sources/N1KOState/Views/Agent/AgentSurfaceViews.swift)
            if [[ ! "$content" =~ ^[[:space:]]*// ]]; then
                printf '%s:%s:%s\n' "$file" "$line" "$content" >&2
                violations=1
            fi
            ;;
        Sources/N1KOState/Views/PingParity/*)
            # Pinned source headers and N1KO modification notices may name
            # the attributed upstream project; executable identifiers may not.
            if [[ ! "$content" =~ ^[[:space:]]*// ]]; then
                printf '%s:%s:%s\n' "$file" "$line" "$content" >&2
                violations=1
            fi
            ;;
        *)
            printf '%s:%s:%s\n' "$file" "$line" "$content" >&2
            violations=1
            ;;
    esac
done < <(rg -n -i "$pattern" \
    Sources Tools Resources Localization Package.swift build_app.sh README.md \
    THIRD_PARTY_NOTICES.md ThirdPartyLicenses || true)

if [[ "$violations" -ne 0 ]]; then
    echo "WP5 identity gate failed: non-N1KO product identity escaped the allowlist." >&2
    exit 1
fi

echo "WP5 identity gate passed: legacy identity is confined to legal notices and migration-only code."
