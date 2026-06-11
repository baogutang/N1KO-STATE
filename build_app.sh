#!/usr/bin/env bash
#
# build_app.sh — Compile N1KO-STATE and assemble a runnable .app bundle.
#
# Usage:
#   ./build_app.sh              # universal (arm64 + x86_64) release build
#   ./build_app.sh --native     # build only for the host architecture (faster)
#   ./build_app.sh --debug      # debug config (implies --native)
#   ./build_app.sh --dmg        # also create a distributable DMG
#
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="N1KO-STATE"
PRODUCT="N1KOState"
BUNDLE_ID="com.n1ko.state.monitor"
CONFIG="release"
ARCH_FLAGS=(--arch arm64 --arch x86_64)
MAKE_DMG=false
RUN_SMOKE=false
# Optional formal signing (requires Apple Developer Program):
#   export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   export NOTARY_PROFILE="your-notarytool-profile"
# When set, build_app.sh uses real codesign + notarytool + stapler instead of ad-hoc.
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

for arg in "$@"; do
    case "$arg" in
        --native) ARCH_FLAGS=() ;;
        --debug)  CONFIG="debug"; ARCH_FLAGS=() ;;
        --dmg)    MAKE_DMG=true ;;
        --smoke)  RUN_SMOKE=true ;;
        *) echo "Unknown option: $arg"; exit 1 ;;
    esac
done

# Generate app icon if missing
if [[ ! -f Resources/AppIcon.icns ]]; then
    echo "==> Generating app icon..."
    swift scripts/gen_icon.swift
fi

echo "==> Building ($CONFIG) ${ARCH_FLAGS[*]:-native}..."
swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}

BIN_PATH="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"
EXE="$BIN_PATH/$PRODUCT"

if [[ ! -f "$EXE" ]]; then
    echo "!! Executable not found at $EXE" >&2
    exit 1
fi

APP_DIR="build/${APP_NAME}.app"
echo "==> Assembling $APP_DIR..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$EXE" "$APP_DIR/Contents/MacOS/$PRODUCT"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# App icon
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

# Privileged fan-control helper
HELPER="$BIN_PATH/FanHelper"
if [[ -f "$HELPER" ]]; then
    echo "==> Bundling fan helper (n1ko-fanctl)..."
    cp "$HELPER" "$APP_DIR/Contents/MacOS/n1ko-fanctl"
fi

# Localizations
if [[ -d Localization ]]; then
    echo "==> Copying localizations..."
    for lproj in Localization/*.lproj; do
        [[ -d "$lproj" ]] || continue
        cp -R "$lproj" "$APP_DIR/Contents/Resources/"
    done
fi

# Code signing.
# Ad-hoc: pin identifiers with -i so the fan daemon accepts the client.
# Developer ID: set SIGN_IDENTITY (and optionally NOTARY_PROFILE + TEAM_ID).
TEAM_ID="${TEAM_ID:-}"
if [[ -n "$SIGN_IDENTITY" && -z "$TEAM_ID" ]]; then
    TEAM_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep "$SIGN_IDENTITY" | head -1 | sed -n 's/.*(\([^)]*\)).*/\1/p')"
fi
if [[ -n "$TEAM_ID" ]]; then
    /usr/libexec/PlistBuddy -c "Add :N1KOTeamID string $TEAM_ID" "$APP_DIR/Contents/Info.plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Set :N1KOTeamID $TEAM_ID" "$APP_DIR/Contents/Info.plist"
fi

SIGN_ARGS=(--force --options runtime)
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Developer ID code signing ($SIGN_IDENTITY)..."
    SIGN_ARGS+=(--sign "$SIGN_IDENTITY")
else
    echo "==> Ad-hoc code signing..."
    SIGN_ARGS+=(--sign -)
fi

HELPER_BIN="$APP_DIR/Contents/MacOS/n1ko-fanctl"
if [[ -f "$HELPER_BIN" ]]; then
    codesign "${SIGN_ARGS[@]}" -i "${BUNDLE_ID}.helper" "$HELPER_BIN" 2>/dev/null || \
        echo "   (helper codesign skipped/failed)"
fi
codesign "${SIGN_ARGS[@]}" -i "$BUNDLE_ID" "$APP_DIR/Contents/MacOS/$PRODUCT" 2>/dev/null || true
codesign "${SIGN_ARGS[@]}" -i "$BUNDLE_ID" "$APP_DIR" 2>/dev/null || \
    echo "   (codesign skipped/failed — app still runs locally)"

echo ""
echo "✅ Built: $APP_DIR"
echo "   Architectures: $(lipo -archs "$APP_DIR/Contents/MacOS/$PRODUCT" 2>/dev/null || echo 'n/a')"

# DMG packaging
if $MAKE_DMG; then
    ARCHS=$(lipo -archs "$APP_DIR/Contents/MacOS/$PRODUCT" 2>/dev/null || echo "")
    case "$ARCHS" in
        *arm64*x86_64*|*x86_64*arm64*) : ;;
        *) echo "!! DMG must be universal (got: $ARCHS)" >&2; exit 1 ;;
    esac

    DMG_NAME="${APP_NAME}.dmg"
    DMG_PATH="build/${DMG_NAME}"
    DMG_TMP="build/dmg-staging"
    echo ""
    echo "==> Creating DMG..."

    rm -rf "$DMG_TMP" "$DMG_PATH"
    mkdir -p "$DMG_TMP"
    cp -R "$APP_DIR" "$DMG_TMP/"
    ln -s /Applications "$DMG_TMP/Applications"

    cat > "$DMG_TMP/安装必读.txt" <<'EOF'
N1KO-STATE 安装说明 / Installation Notes
=====================================

【中文】
若首次打开提示「已损坏，无法打开」或 Gatekeeper 拦截，这是因为本应用为 ad-hoc 签名（未经 Apple 公证）。

解决方法（任选其一）：
1. 双击运行同目录下的「修复打不开.command」
2. 在终端执行：xattr -cr /Applications/N1KO-STATE.app
3. 右键应用 → 打开（仅首次需要）

【English】
If macOS says the app is "damaged" or won't open, this is due to ad-hoc signing (not notarized).

Fix (pick one):
1. Double-click "修复打不开.command" in this DMG folder
2. Run in Terminal: xattr -cr /Applications/N1KO-STATE.app
3. Right-click the app → Open (first launch only)
EOF

    cat > "$DMG_TMP/修复打不开.command" <<'EOF'
#!/bin/bash
xattr -cr /Applications/N1KO-STATE.app 2>/dev/null || true
echo "完成 / Done — you can now open N1KO-STATE."
read -r -p "Press Enter to close…" _
EOF
    chmod +x "$DMG_TMP/修复打不开.command"

    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$DMG_TMP" \
        -ov -format UDZO \
        "$DMG_PATH" 2>/dev/null

    rm -rf "$DMG_TMP"
    echo "✅ DMG: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"

    if [[ -n "$SIGN_IDENTITY" && -n "$NOTARY_PROFILE" ]]; then
        echo "==> Notarizing DMG (profile: $NOTARY_PROFILE)..."
        xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG_PATH"
        echo "✅ Notarized and stapled: $DMG_PATH"
    fi
    echo ""
    echo "Distribution:"
    echo "   Share $DMG_PATH — recipients open the DMG and drag to Applications."
    echo "   First launch: right-click → Open (bypasses Gatekeeper for ad-hoc signed apps)."
fi

if $RUN_SMOKE; then
    echo ""
    echo "==> Smoke test..."
    LOG=~/Library/Logs/N1KO-STATE/launch.log
    pkill -x "$PRODUCT" 2>/dev/null || true
    sleep 1
    rm -f "$LOG"
    open "$APP_DIR"
    sleep 6
    PID=$(pgrep -x "$PRODUCT" || true)
    if [[ -z "$PID" ]]; then
        echo "❌ SMOKE: process died"
        exit 1
    fi
    if ! grep -q "applicationDidFinishLaunching" "$LOG" 2>/dev/null; then
        echo "❌ SMOKE: app launched but never finished launching (main thread blocked?)"
        sample "$PRODUCT" 3 -file /tmp/n1ko_smoke_sample.txt 2>/dev/null || true
        echo "   stack sample: /tmp/n1ko_smoke_sample.txt"
        exit 1
    fi
    CPU=$(top -l 3 -s 2 -pid "$PID" -stats cpu 2>/dev/null | grep -E '^[0-9]' | tail -1)
    echo "✅ SMOKE passed (idle cpu sample: ${CPU:-n/a}%)"
    pkill -x "$PRODUCT" || true
fi

echo ""
echo "Run it with:"
echo "   open \"$APP_DIR\""
echo "Or install:"
echo "   cp -R \"$APP_DIR\" /Applications/"
