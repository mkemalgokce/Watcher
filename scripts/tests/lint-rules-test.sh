#!/usr/bin/env bash
# Runs the custom SwiftLint rules over fixtures and compares the violations with the expected set.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
fixtures="$root/scripts/tests/fixtures/lint"
custom_rules='no_print|no_live_singletons|design_system_colors'

violation='^.*/(Sources/[^:]+):([0-9]+):[0-9]+: error: .*\(('"$custom_rules"')\)$'
# SwiftLint lints the paths of the config it is given, so lint a copy laid out like the repository.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cp -R "$fixtures/Sources" "$root/.swiftlint.yml" "$workdir/"

# Lint exits non-zero because the fixtures violate rules; a crash shows up as a missing violation below.
output="$(cd "$workdir" && "$root/.tools/swiftlint" lint --quiet 2>&1)" || true
actual="$(sed -nE "s#${violation}#\\1:\\2 \\3#p" <<< "$output" | sort)"

expected="$(sort <<'LIST'
Sources/WatcherCore/Probe.swift:7 no_print
Sources/WatcherCore/Probe.swift:8 no_live_singletons
Sources/WatcherCore/Probe.swift:9 design_system_colors
Sources/WatcherCore/Probe.swift:10 design_system_colors
Sources/WatcherCore/Probe.swift:11 design_system_colors
Sources/WatcherCore/Probe.swift:12 design_system_colors
LIST
)"

if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: custom lint rules"
    diff <(echo "$expected") <(echo "$actual") || true
    exit 1
fi
echo "all cases passed"
