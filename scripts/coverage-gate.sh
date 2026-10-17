#!/usr/bin/env bash
# Fails when line coverage in an lcov file falls below the thresholds file.
# Usage: coverage-gate.sh <coverage.lcov> <thresholds>; each threshold line is "<Sources/Prefix> <percent>" or "TOTAL <percent>".
set -euo pipefail

lcov="$1"
thresholds="$2"

if [[ ! -s "$lcov" ]] || ! grep -q '^SF:' "$lcov"; then
    echo "coverage gate: no coverage data in '$lcov'" >&2
    exit 1
fi
if ! grep -q '[^[:space:]]' "$thresholds" 2> /dev/null; then
    echo "coverage gate: no thresholds in '$thresholds'" >&2
    exit 1
fi
if invalid="$(grep -vnE '^[^[:space:]]+ [0-9]+(\.[0-9]+)?$' "$thresholds")"; then
    echo "coverage gate: invalid threshold line in '$thresholds': $invalid" >&2
    exit 1
fi

awk -v summary="${GITHUB_STEP_SUMMARY:-}" '
    NR == FNR { order[++count] = $1; limit[$1] = $2; next }
    /^SF:/ { file = substr($0, 4); next }
    /^LF:/ { found = substr($0, 4) + 0; next }
    /^LH:/ {
        hit = substr($0, 4) + 0
        lines["TOTAL"] += found; covered["TOTAL"] += hit
        for (i = 1; i <= count; i++) {
            prefix = order[i]
            if (prefix != "TOTAL" && index(file, "/" prefix "/")) { lines[prefix] += found; covered[prefix] += hit }
        }
    }
    END {
        status = 0
        if (summary != "") { print "| Module | Line coverage | Threshold |\n|---|---|---|" >> summary }
        for (i = 1; i <= count; i++) {
            prefix = order[i]
            if (lines[prefix] + 0 == 0) { printf "%s has no measured lines\n", prefix; status = 1; continue }
            percent = covered[prefix] * 100 / lines[prefix]
            passed = percent >= limit[prefix]
            printf "%s %.2f%% %s %s%%\n", prefix, percent, passed ? ">=" : "<", limit[prefix]
            if (!passed) status = 1
            if (summary != "") printf "| %s | %.2f%% | %s%% |\n", prefix, percent, limit[prefix] >> summary
        }
        exit status
    }
' "$thresholds" "$lcov"
