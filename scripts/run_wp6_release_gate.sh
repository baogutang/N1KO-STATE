#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP="$ROOT/build/N1KO-STATE.app"
MAIN="$APP/Contents/MacOS/N1KOState"
BRIDGE="$APP/Contents/MacOS/n1ko-agent-bridge"

[[ -x "$MAIN" && -x "$BRIDGE" ]] || {
    echo "WP6 release gate requires an existing native build/N1KO-STATE.app" >&2
    exit 66
}

plutil -lint Resources/Info.plist Localization/*/Localizable.strings

duplicate_failure=0
for localization in Localization/*.lproj/Localizable.strings; do
    duplicates="$(sed -n 's/^"\([^"]*\)"[[:space:]]*=.*/\1/p' "$localization" | sort | uniq -d)"
    if [[ -n "$duplicates" ]]; then
        echo "duplicate localization keys in $localization:" >&2
        echo "$duplicates" >&2
        duplicate_failure=1
    fi
done
(( duplicate_failure == 0 )) || exit 1

required_notices=(
    THIRD_PARTY_NOTICES.md
    ThirdPartyLicenses/Ping-Island-Apache-2.0.txt
    ThirdPartyLicenses/Ping-Island-NOTICE.txt
    ThirdPartyLicenses/SMCKit-MIT.txt
    ThirdPartyLicenses/Sparkle-LICENSE.txt
)
for notice in "${required_notices[@]}"; do
    [[ -s "$notice" ]] || { echo "missing or empty legal notice: $notice" >&2; exit 1; }
done

for bundled in \
    "$APP/Contents/Resources/ThirdPartyNotices/NOTICE.md" \
    "$APP/Contents/Resources/ThirdPartyNotices/Licenses/Ping-Island-Apache-2.0.txt" \
    "$APP/Contents/Resources/ThirdPartyNotices/Licenses/Ping-Island-NOTICE.txt" \
    "$APP/Contents/Resources/ThirdPartyNotices/Licenses/SMCKit-MIT.txt" \
    "$APP/Contents/Resources/ThirdPartyNotices/Licenses/Sparkle-LICENSE.txt"; do
    [[ -s "$bundled" ]] || { echo "legal notice not bundled: $bundled" >&2; exit 1; }
done

SOUND_MANIFEST="Resources/Sounds/SHA256SUMS"
[[ -s "$SOUND_MANIFEST" ]] || { echo "missing pinned sound manifest" >&2; exit 1; }
[[ "$(wc -l < "$SOUND_MANIFEST" | tr -d ' ')" == "13" ]] || {
    echo "pinned sound manifest must contain exactly 13 entries" >&2
    exit 1
}
shasum -a 256 -c "$SOUND_MANIFEST"
[[ "$(find "$APP/Contents/Resources/Sounds" -type f -name '*.wav' | wc -l | tr -d ' ')" == "13" ]] || {
    echo "native bundle must contain exactly 13 pinned WAV files" >&2
    exit 1
}
while read -r expected source; do
    bundled_sound="$APP/Contents/Resources/Sounds/${source##*/}"
    [[ -f "$bundled_sound" ]] || { echo "pinned sound not bundled: ${source##*/}" >&2; exit 1; }
    actual="$(shasum -a 256 "$bundled_sound" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || {
        echo "pinned sound hash mismatch in bundle: ${source##*/}" >&2
        exit 1
    }
done < "$SOUND_MANIFEST"

modified_sources=(AgentEvents.swift AgentModels.swift AgentParsers.swift AgentSessionStore.swift)
for source in "${modified_sources[@]}"; do
    head -1 "Sources/N1KOAgentCore/$source" | grep -q '^// N1KO modification notice:' || {
        echo "missing modification marker: Sources/N1KOAgentCore/$source" >&2
        exit 1
    }
done

./scripts/run_wp5_identity_gate.sh

feed_url="$(plutil -extract SUFeedURL raw -o - Resources/Info.plist)"
[[ "$feed_url" == "https://raw.githubusercontent.com/baogutang/N1KO-STATE/main/appcast.xml" ]] || {
    echo "unexpected update feed: $feed_url" >&2
    exit 1
}
rg -q 'static let feedURL = "https://raw\.githubusercontent\.com/baogutang/N1KO-STATE/main/appcast\.xml"' \
    Sources/N1KOState/App/UpdateController.swift || {
        echo "UpdateController and Info.plist feed identities differ" >&2
        exit 1
    }

if rg --pcre2 -n '\bCGS(?!ize)[A-Za-z0-9_]*|\bSLS[A-Za-z0-9_]*|SkyLight' \
    Sources/N1KOState Sources/N1KOAgentCore Sources/N1KOWindowCore Tools; then
    echo "private CGS/SLS/SkyLight source reference found" >&2
    exit 1
fi
if nm -u "$MAIN" "$BRIDGE" 2>/dev/null | rg --pcre2 '_CGS(?!ize)|_SLS|SkyLight'; then
    echo "private CGS/SLS/SkyLight linked symbol found" >&2
    exit 1
fi

owner_count() {
    local pattern="$1" expected="$2" label="$3" count
    count="$(rg -n "$pattern" Sources | wc -l | tr -d ' ')"
    [[ "$count" == "$expected" ]] || {
        echo "$label ownership count is $count, expected $expected" >&2
        exit 1
    }
}
owner_count '^@main' 1 '@main'
owner_count '^final class AppDelegate' 1 AppDelegate
owner_count '^final class SettingsWindowController' 1 SettingsWindowController
owner_count '^final class UpdateController' 1 UpdateController
owner_count '^final class PresentationCoordinator' 1 PresentationCoordinator
owner_count '^public final class AgentSessionCoordinator' 1 AgentSessionCoordinator

for binary in "$MAIN" "$BRIDGE"; do
    minos="$(otool -l "$binary" | awk '$1 == "minos" { print $2 }' | sort -u)"
    [[ "$minos" == "12.0" ]] || { echo "$binary minos is $minos, expected 12.0" >&2; exit 1; }
done

codesign --verify --deep --strict --verbose=2 "$APP"
codesign --verify --strict --verbose=2 "$BRIDGE"
git diff --check

echo "WP6 release gate passed: localization uniqueness, legal and pinned-sound bundle, identity/feed, ownership, public fullscreen APIs, minos 12.0, signatures, and diff hygiene are clean."
