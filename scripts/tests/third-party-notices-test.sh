#!/usr/bin/env bash
# Table test for scripts/third-party-notices.sh. It runs a copy in a scratch folder holding a fixture Package.resolved
# and fixture checkouts, so no network and no real .build are needed.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/third-party-notices.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
mkdir -p "$workdir/scripts"
cp "$script" "$workdir/scripts/third-party-notices.sh"
failures=0

# fail <message>
fail() {
    echo "FAIL: $1"
    failures=$((failures + 1))
}

# pins <identity|location|state-json>...  writes Package.resolved in the order given
pins() {
    local entries=() spec
    for spec in "$@"; do
        IFS='|' read -r identity location state <<< "$spec"
        entries+=("{\"identity\":\"$identity\",\"location\":\"$location\",\"state\":$state}")
    done
    local joined
    joined="$(IFS=,; echo "${entries[*]}")"
    printf '{"pins":[%s]}\n' "$joined" > "$workdir/Package.resolved"
}

# checkout <name> <relative file> <text>
checkout() {
    mkdir -p "$workdir/.build/checkouts/$1/$(dirname "$2")"
    printf '%s\n' "$3" > "$workdir/.build/checkouts/$1/$2"
}

# run <expected exit> <expected text>   runs the copy and checks its exit status and its output (or the file it wrote)
run() {
    local expected_status="$1" expected_text="$2" output status=0
    output="$(bash "$workdir/scripts/third-party-notices.sh" "$workdir/out.md" 2>&1)" || status=$?
    [[ -f "$workdir/out.md" && "$status" -eq 0 ]] && output="$output$(cat "$workdir/out.md")"
    if [[ "$status" -ne "$expected_status" || "$output" != *"$expected_text"* ]]; then
        fail "expected exit $expected_status with '$expected_text'; got exit $status: $output"
    fi
}

reset() {
    rm -rf "$workdir/.build" "$workdir/out.md" "$workdir/Package.resolved"
}

reset
pins "alpha|https://example.com/alpha.git|{\"version\":\"1.0.0\"}"
run 1 "alpha is missing; run swift package resolve first"

reset
pins "alpha|https://example.com/alpha.git|{\"version\":\"1.0.0\"}"
mkdir -p "$workdir/.build/checkouts/alpha"
checkout alpha README.md "no licence here"
run 1 "no licence file found for alpha"

reset
pins "alpha|https://example.com/alpha.git|{\"version\":\"1.0.0\"}"
checkout alpha LICENSE "alpha licence text"
run 0 "## alpha 1.0.0"
run 0 "alpha licence text"

reset
pins "beta|https://example.com/beta.git|{\"revision\":\"abc123\"}"
checkout beta NOTICE "beta notice text"
run 0 "## beta abc123"

reset
pins "gamma|https://example.com/gamma.git|{\"version\":\"2.0.0\"}"
checkout gamma LICENSE "gamma licence"
checkout gamma Sources/llhttp/LICENSE-MIT "vendored licence text"
run 0 "### Sources/llhttp/LICENSE-MIT"
run 0 "vendored licence text"

reset
pins "zeta|https://example.com/zeta|{\"version\":\"1.0.0\"}" "alpha|https://example.com/alpha.git|{\"version\":\"1.0.0\"}"
checkout zeta LICENSE "zeta licence"
checkout alpha LICENSE "alpha licence"
run 0 "## alpha 1.0.0"
if [[ "$(grep -n '^## ' "$workdir/out.md" | cut -d' ' -f2 | tr '\n' ' ')" != "alpha zeta " ]]; then
    fail "packages are not sorted by identity: $(grep '^## ' "$workdir/out.md" | tr '\n' ' ')"
fi

if [[ "$failures" -gt 0 ]]; then
    echo "$failures case(s) failed"
    exit 1
fi
echo "all cases passed"
