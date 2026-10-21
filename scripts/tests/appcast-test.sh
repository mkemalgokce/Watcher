#!/usr/bin/env bash
# Table test for scripts/appcast.sh. SIGN_UPDATE points at a stub that records how it was called and prints what Sparkle's
# sign_update prints, so no key or Sparkle build is needed.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/appcast.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
dmg="$workdir/Watcher-1.2.3.dmg"
out="$workdir/appcast.xml"
printf 'disk image' > "$dmg"
failures=0

cat > "$workdir/sign_update" <<'STUB'
#!/bin/bash
cat > "$STUB_DIR/stdin"
echo "$*" > "$STUB_DIR/args"
[[ -z "${STUB_FAIL:-}" ]] || exit 3
echo "${STUB_OUTPUT-sparkle:edSignature=\"SIG==\" length=\"10\"}"
STUB
chmod +x "$workdir/sign_update"

# run <env assignments...> -- <arguments...>: leaves the output in $output and the exit status in $status
run() {
    local assignments=()
    while [[ "$1" != "--" ]]; do assignments+=("$1"); shift; done
    shift
    status=0
    rm -f "$out" "$workdir/stdin" "$workdir/args"
    output="$(env -u SPARKLE_PRIVATE_KEY -u STUB_FAIL -u STUB_OUTPUT STUB_DIR="$workdir" SIGN_UPDATE="$workdir/sign_update" \
        ${assignments[@]+"${assignments[@]}"} bash "$script" "$@" 2>&1)" || status=$?
}

# check <expected exit> <expected text> <env assignments...> -- <arguments...>
check() {
    local expected_status="$1" expected_text="$2"
    shift 2
    run "$@"
    if [[ "$status" -ne "$expected_status" || "$output" != *"$expected_text"* ]]; then
        echo "FAIL: expected exit $expected_status with '$expected_text'; got exit $status: $output"
        failures=$((failures + 1))
    fi
}

# expect <description> <text>: the feed written by the last run contains <text>
expect() {
    if ! grep -qF -- "$2" "$out" 2>/dev/null; then
        echo "FAIL: $1: the feed lacks '$2'"
        failures=$((failures + 1))
    fi
}

check 1 "usage: appcast.sh" -- 
check 1 "usage: appcast.sh" -- 1.2.3 7 "$dmg"
check 1 "version must look like 1.2.3: v1.2.3" SPARKLE_PRIVATE_KEY=k -- v1.2.3 7 "$dmg" "$out"
check 1 "version must look like 1.2.3: 1.2" SPARKLE_PRIVATE_KEY=k -- 1.2 7 "$dmg" "$out"
check 1 "build number must be an integer: 7a" SPARKLE_PRIVATE_KEY=k -- 1.2.3 7a "$dmg" "$out"
check 1 "disk image not found: $workdir/missing.dmg" SPARKLE_PRIVATE_KEY=k -- 1.2.3 7 "$workdir/missing.dmg" "$out"
check 1 "SPARKLE_PRIVATE_KEY is missing" -- 1.2.3 7 "$dmg" "$out"
check 1 "could not sign" SPARKLE_PRIVATE_KEY=k STUB_FAIL=1 -- 1.2.3 7 "$dmg" "$out"
check 1 "no signature in the output of sign_update" SPARKLE_PRIVATE_KEY=k STUB_OUTPUT=nothing -- 1.2.3 7 "$dmg" "$out"
[[ ! -e "$out" ]] || { echo "FAIL: a feed was written although signing failed"; failures=$((failures + 1)); }

check 0 "Wrote $out" SPARKLE_PRIVATE_KEY=secret-key GITHUB_REPOSITORY=owner/App -- 1.2.3 7 "$dmg" "$out"
expect "the item names the build Sparkle compares" "<sparkle:version>7</sparkle:version>"
expect "the item names the version people read" "<sparkle:shortVersionString>1.2.3</sparkle:shortVersionString>"
expect "the download is the release's disk image" 'url="https://github.com/owner/App/releases/download/v1.2.3/Watcher-1.2.3.dmg"'
expect "the signature comes from sign_update" 'sparkle:edSignature="SIG==" length="10"'
expect "the release notes are the release page" "https://github.com/owner/App/releases/tag/v1.2.3"
expect "older systems are not offered the update" "<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>"
[[ "$(cat "$workdir/stdin")" == "secret-key" ]] || { echo "FAIL: the key did not reach sign_update on stdin"; failures=$((failures + 1)); }
if grep -q "secret-key" "$workdir/args"; then
    echo "FAIL: the key was passed as an argument, where other processes can read it"
    failures=$((failures + 1))
fi
grep -qF -- "--ed-key-file -" "$workdir/args" || { echo "FAIL: sign_update was not told to read the key from stdin"; failures=$((failures + 1)); }

check 0 "Wrote $out" SPARKLE_PRIVATE_KEY=k -- 1.2.3-beta.1 7 "$dmg" "$out"
expect "a prerelease keeps its full version" "<sparkle:shortVersionString>1.2.3-beta.1</sparkle:shortVersionString>"
check 0 "Wrote $out" SPARKLE_PRIVATE_KEY=k -- 1.2.3 7 "$dmg" "$out"
expect "the repository defaults to this one" "https://github.com/mkemalgokce/Watcher/releases/download/v1.2.3/"

if [[ "$failures" -gt 0 ]]; then
    echo "$failures case(s) failed"
    exit 1
fi
echo "all cases passed"
