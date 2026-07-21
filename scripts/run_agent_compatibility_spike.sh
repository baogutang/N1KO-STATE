#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DEVELOPER_DIR="${BUILD_DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
export DEVELOPER_DIR="$BUILD_DEVELOPER_DIR"
UPSTREAM_URL="https://github.com/erha19/ping-island.git"
UPSTREAM_COMMIT="da130d679e830894240e926184d29751dfd2def1"
DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET:-12.0}"
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macosx$DEPLOYMENT_TARGET"
OUTPUT="${1:-$ROOT/docs/roadmap/evidence/wp0/agent-compatibility-spike.md}"
WORK="$(mktemp -d -t n1ko-agent-compat)"
trap 'rm -rf "$WORK"' EXIT

git clone --filter=blob:none --no-checkout "$UPSTREAM_URL" "$WORK/repo" >/dev/null
git -C "$WORK/repo" fetch --depth 1 origin "$UPSTREAM_COMMIT" >/dev/null
mkdir -p "$WORK/source"
git -C "$WORK/repo" archive FETCH_HEAD | tar -x -C "$WORK/source"

SOURCE="$WORK/source/PingIsland"
sed -n '2227,2285p' "$SOURCE/Services/Hooks/HookSocketServer.swift" > "$WORK/AnyCodable-body.swift"
sed '1i\
import Foundation\
' "$WORK/AnyCodable-body.swift" > "$WORK/AnyCodable.swift"
sed -n '123,$p' "$SOURCE/Services/Chat/ChatHistoryManager.swift" > "$WORK/ChatHistoryTypes-body.swift"
sed '1i\
import Foundation\
' "$WORK/ChatHistoryTypes-body.swift" > "$WORK/ChatHistoryTypes.swift"
sed -n '1180,1336p' "$SOURCE/Services/Hooks/HookSocketServer.swift" > "$WORK/CodexAuxiliaryHookFilter-body.swift"
sed '1i\
import Foundation\
' "$WORK/CodexAuxiliaryHookFilter-body.swift" > "$WORK/CodexAuxiliaryHookFilter.swift"

COMMON_SOURCES=(
    "$WORK/AnyCodable.swift"
    "$WORK/ChatHistoryTypes.swift"
    "$WORK/CodexAuxiliaryHookFilter.swift"
    "$SOURCE/Models/ChatMessage.swift"
    "$SOURCE/Models/ToolResultData.swift"
    "$SOURCE/Models/SessionPhase.swift"
    "$SOURCE/Models/SessionProvider.swift"
    "$SOURCE/Models/ClientProfile.swift"
    "$SOURCE/Services/Shared/TerminalAppRegistry.swift"
    "$SOURCE/Services/Window/IDEExtensionInstaller.swift"
    "$SOURCE/Utilities/SessionTextSanitizer.swift"
    "$SOURCE/Services/Session/ConversationParser.swift"
    "$SOURCE/Services/Codex/CodexThreadSnapshot.swift"
)

set +e
xcrun swiftc -typecheck -target "$TARGET" -swift-version 5 \
    "${COMMON_SOURCES[@]}" \
    "$SOURCE/Services/Codex/CodexRolloutParser.swift" \
    > "$WORK/upstream.stdout" 2> "$WORK/upstream.stderr"
UPSTREAM_STATUS=$?
set -e

if [[ "$UPSTREAM_STATUS" -eq 0 ]] || ! rg -q "only available in macOS 13.0 or newer" "$WORK/upstream.stderr"; then
    echo "Expected the pinned parser to expose its macOS 13 API boundary" >&2
    cat "$WORK/upstream.stderr" >&2
    exit 1
fi

cp "$SOURCE/Services/Codex/CodexRolloutParser.swift" "$WORK/CodexRolloutParser-macOS12.swift"
perl -0pi -e 's/tool\.name\.split\(separator: "__", omittingEmptySubsequences: false\)/tool.name.components(separatedBy: "__")/' \
    "$WORK/CodexRolloutParser-macOS12.swift"

xcrun swiftc -typecheck -target "$TARGET" -swift-version 5 \
    "${COMMON_SOURCES[@]}" \
    "$WORK/CodexRolloutParser-macOS12.swift" \
    > "$WORK/adapted.stdout" 2> "$WORK/adapted.stderr"

cat > "$WORK/StoreSupport.swift" <<'EOF'
import Foundation

enum SessionProvider: String, Codable, Equatable, Sendable { case claude, codex }
struct SessionClientInfo: Codable, Equatable, Sendable { let name: String }
struct SessionState: Equatable, Sendable {
    let provider: SessionProvider
    let sessionId: String
    let cwd: String
    let projectName: String
    let clientInfo: SessionClientInfo
    let sessionName: String?
}
struct ClaudeUsageSnapshot: Codable {}
struct CodexUsageSnapshot: Codable {}
EOF

xcrun swiftc -typecheck -target "$TARGET" -swift-version 5 \
    "$WORK/StoreSupport.swift" \
    "$SOURCE/Services/State/SessionAssociationStore.swift" \
    "$SOURCE/Services/Usage/UsageSnapshotCacheStore.swift" \
    > "$WORK/store.stdout" 2> "$WORK/store.stderr"

mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<EOF
# WP0 Agent compatibility spike

- Run date: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- Upstream: \`$UPSTREAM_URL\`
- Commit: \`$UPSTREAM_COMMIT\`
- Compiler: \`$(swift --version | head -1)\`
- Target: \`$TARGET\`
- Swift language mode: 5

## Slice

The spike typechecks the pinned Agent models, client-profile boundary, Claude conversation parser,
Codex rollout parser and thread snapshot, plus the exact association and usage cache stores. Small
support excerpts are extracted from the same commit only to avoid pulling the socket server and live
session singleton into the spike.

## Result

- Unmodified slice: expected failure at \`PingIsland/Services/Codex/CodexRolloutParser.swift:531\`.
- Incompatible API: \`String.split(separator: "__", omittingEmptySubsequences: false)\` resolves to
  the multi-character overload that is macOS 13+.
- macOS 12 adaptation: replace that call with \`components(separatedBy: "__")\`; the complete
  selected model/parser group then typechecks.
- Store slice: the unmodified association and usage cache stores typecheck for macOS 12 behind
  boundary stubs.
- Backport estimate: low for this representative slice (one parser call plus N1KO-owned runtime
  paths); broader WP3 ports still require per-file availability checks.

## Decision evidence

This spike does not justify raising N1KO-STATE's minimum from macOS 12. It supports preserving macOS
12 and isolating newer APIs behind adapters or availability checks.
EOF

echo "Agent compatibility evidence: $OUTPUT"
