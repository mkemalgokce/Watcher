#!/usr/bin/env bash
# Table test for scripts/coverage-gate.sh.
set -euo pipefail

gate="$(cd "$(dirname "$0")/.." && pwd)/coverage-gate.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
failures=0

# record <path> <lines> <hit>: one lcov record.
record() { printf 'SF:%s\nDA:1,1\nLF:%s\nLH:%s\nend_of_record\n' "$1" "$2" "$3"; }

check() {
    local expected_status="$1" lcov="$2" thresholds="$3" expected_text="$4" output status=0
    printf '%s' "$lcov" > "$workdir/coverage.lcov"
    printf '%s' "$thresholds" > "$workdir/thresholds.txt"
    output="$(GITHUB_STEP_SUMMARY='' "$gate" "$workdir/coverage.lcov" "$workdir/thresholds.txt" 2>&1)" || status=$?
    if [[ "$status" -ne "$expected_status" || "$output" != *"$expected_text"* ]]; then
        echo "FAIL: expected exit $expected_status with '$expected_text'; got exit $status: $output"
        failures=$((failures + 1))
    fi
}

modules=$'Sources/WatcherCore 90\nSources/WatcherUI 80\nTOTAL 85\n'
total_only=$'TOTAL 85\n'

check 0 "$(record /r/Sources/WatcherCore/URL/A.swift 100 90; record /r/Sources/WatcherCore/B.swift 100 100; record /r/Sources/WatcherUI/C.swift 100 90)" \
    "$modules" "Sources/WatcherCore 95.00% >= 90%"
check 1 "$(record /r/Sources/WatcherCore/A.swift 1000 899; record /r/Sources/WatcherUI/C.swift 100 100)" \
    "$modules" "Sources/WatcherCore 89.90% < 90%"
check 1 "$(record /r/Sources/WatcherCore/A.swift 200 169)" "$total_only" "TOTAL 84.50% < 85%"
check 0 "$(record /r/Sources/WatcherCore/A.swift 200 170)" "$total_only" "TOTAL 85.00% >= 85%"
check 0 "$(record '/my repo/Sources/WatcherCore/A.swift' 10 10)" $'Sources/WatcherCore 90\n' \
    "Sources/WatcherCore 100.00%"
check 0 "$(record /r/Sources/WatcherCore/A.swift 10 10; record /r/Sources/WatcherCoreExtras/B.swift 10 0)" \
    $'Sources/WatcherCore 90\n' "Sources/WatcherCore 100.00%"
check 1 "$(record /r/Sources/WatcherCore/A.swift 10 10)" $'Sources/WatcherMissing 90\nTOTAL 85\n' \
    "Sources/WatcherMissing has no measured lines"
check 1 "" "$modules" "no coverage data"
check 1 "$(record /r/Sources/WatcherCore/A.swift 10 10)" "" "no thresholds"
check 1 "$(record /r/Sources/WatcherCore/A.swift 10 10)" $'Sources/WatcherCore\n' "invalid threshold line"

if "$gate" "$workdir/does-not-exist.lcov" "$workdir/thresholds.txt" > /dev/null 2>&1; then
    echo "FAIL: a missing report passed"
    failures=$((failures + 1))
fi

record /r/Sources/WatcherUI/C.swift 100 90 > "$workdir/coverage.lcov"
printf 'Sources/WatcherUI 80\n' > "$workdir/thresholds.txt"
GITHUB_STEP_SUMMARY="$workdir/summary.md" "$gate" "$workdir/coverage.lcov" "$workdir/thresholds.txt" > /dev/null
if ! grep -q '| Sources/WatcherUI | 90.00% | 80% |' "$workdir/summary.md"; then
    echo "FAIL: job summary table missing; got: $(cat "$workdir/summary.md")"
    failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
    echo "$failures case(s) failed"
    exit 1
fi
echo "all cases passed"
