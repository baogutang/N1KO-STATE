#!/usr/bin/env bash
# Compare localization key sets across en / zh-Hans / zh-Hant.
set -euo pipefail
cd "$(dirname "$0")/.."
keys() { grep -o '^"[^"]*"' Localization/$1.lproj/Localizable.strings | sort -u; }
for pair in "en zh-Hans" "en zh-Hant"; do
    read -r a b <<< "$pair"
    if diff <(keys "$a") <(keys "$b") >/dev/null; then
        echo "OK: $a ↔ $b"
    else
        echo "MISMATCH: $a ↔ $b"
        diff <(keys "$a") <(keys "$b") || true
        exit 1
    fi
done
echo "All localization key sets match."
