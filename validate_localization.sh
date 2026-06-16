#!/bin/bash
# validate_localization.sh
# Checks that Localizable.strings keys are consistent across en, zh-Hans, ja, ko.
# Run locally or in CI. Exits 1 on mismatch.

set -e

RESOURCES="Light Stats/Resources"
EN="$RESOURCES/en.lproj/Localizable.strings"
ZH="$RESOURCES/zh-Hans.lproj/Localizable.strings"
JA="$RESOURCES/ja.lproj/Localizable.strings"
KO="$RESOURCES/ko.lproj/Localizable.strings"

extract_keys() {
    grep -o '"[^"]*" = ' "$1" | sed 's/ = $//' | tr -d '"' | sort
}

EN_KEYS=$(extract_keys "$EN")
ZH_KEYS=$(extract_keys "$ZH")
JA_KEYS=$(extract_keys "$JA")
KO_KEYS=$(extract_keys "$KO")

FAIL=0

echo "🔍 Checking localization key coverage..."

# Keys in EN but missing in ZH
while IFS= read -r key; do
    if ! grep -qF "\"$key\"" "$ZH"; then
        echo "  ❌ en → zh-Hans missing: \"$key\""
        FAIL=1
    fi
done <<< "$EN_KEYS"

# Keys in EN but missing in JA
while IFS= read -r key; do
    if ! grep -qF "\"$key\"" "$JA"; then
        echo "  ❌ en → ja missing: \"$key\""
        FAIL=1
    fi
done <<< "$EN_KEYS"

# Keys in EN but missing in KO
while IFS= read -r key; do
    if ! grep -qF "\"$key\"" "$KO"; then
        echo "  ❌ en → ko missing: \"$key\""
        FAIL=1
    fi
done <<< "$EN_KEYS"

# Keys in ZH but missing in EN (stale)
while IFS= read -r key; do
    if ! grep -qF "\"$key\"" "$EN"; then
        echo "  ❌ zh-Hans → en missing: \"$key\""
        FAIL=1
    fi
done <<< "$ZH_KEYS"

# Keys in JA but missing in EN (stale)
while IFS= read -r key; do
    if ! grep -qF "\"$key\"" "$EN"; then
        echo "  ❌ ja → en missing: \"$key\""
        FAIL=1
    fi
done <<< "$JA_KEYS"

# Keys in KO but missing in EN (stale)
while IFS= read -r key; do
    if ! grep -qF "\"$key\"" "$EN"; then
        echo "  ❌ ko → en missing: \"$key\""
        FAIL=1
    fi
done <<< "$KO_KEYS"

if [ "$FAIL" -eq 0 ]; then
    EN_COUNT=$(echo "$EN_KEYS" | wc -l | tr -d ' ')
    echo "  ✅ All $EN_COUNT keys present in en, zh-Hans, ja, ko"
else
    echo ""
    echo "Run: ./validate_localization.sh"
    echo "Fix: add missing keys to all four .lproj/Localizable.strings files"
    exit 1
fi
