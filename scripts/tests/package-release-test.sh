#!/usr/bin/env bash
# Table test for the argument and environment checks of scripts/package-release.sh. It runs a copy in a scratch folder
# whose tools/build-app.sh is a stub exiting 99, so a case that gets past the checks stops before building anything.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/package-release.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$workdir/scripts" "$workdir/tools"
cp "$script" "$workdir/scripts/package-release.sh"
printf '#!/bin/bash\necho "build-app reached"\nexit 99\n' > "$workdir/tools/build-app.sh"
chmod +x "$workdir/tools/build-app.sh"
failures=0

# check <expected exit> <expected text> <env assignments...> -- <arguments...>
check() {
    local expected_status="$1" expected_text="$2" output status=0
    shift 2
    local assignments=()
    while [[ "$1" != "--" ]]; do assignments+=("$1"); shift; done
    shift
    output="$(env -u CODESIGN_IDENTITY -u NOTARY_KEY -u NOTARY_KEY_ID -u NOTARY_ISSUER_ID -u REQUIRE_NOTARIZATION \
        ${assignments[@]+"${assignments[@]}"} bash "$workdir/scripts/package-release.sh" "$@" 2>&1)" || status=$?
    if [[ "$status" -ne "$expected_status" || "$output" != *"$expected_text"* ]]; then
        echo "FAIL: $* expected exit $expected_status with '$expected_text'; got exit $status: $output"
        failures=$((failures + 1))
    fi
}

check 1 "usage: package-release.sh <version> <build-number>" --
check 1 "build number required" -- 1.2.3
check 1 "build number must be an integer: 1.0" -- 1.2.3 1.0
check 1 "build number must be an integer: -1" -- 1.2.3 -1
check 1 "build number must be an integer: 7a" -- 1.2.3 7a
check 1 "REQUIRE_NOTARIZATION=1 needs CODESIGN_IDENTITY" REQUIRE_NOTARIZATION=1 -- 1.2.3 7
check 1 "REQUIRE_NOTARIZATION=1 needs CODESIGN_IDENTITY" REQUIRE_NOTARIZATION=1 CODESIGN_IDENTITY=x NOTARY_KEY=k \
    NOTARY_KEY_ID=i -- 1.2.3 7
check 99 "build-app reached" -- 1.2.3 7
check 99 "build-app reached" REQUIRE_NOTARIZATION=1 CODESIGN_IDENTITY=x NOTARY_KEY=k NOTARY_KEY_ID=i \
    NOTARY_ISSUER_ID=s -- 1.2.3 7

if [[ "$failures" -gt 0 ]]; then
    echo "$failures case(s) failed"
    exit 1
fi
echo "all cases passed"
