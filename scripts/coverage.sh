#!/usr/bin/env bash
# Runs the tests with coverage, writes coverage.lcov (gated) and coverage/report.txt (for reading), then applies the gate.
set -euo pipefail
cd "$(dirname "$0")/.."

swift test --enable-code-coverage "$@"

bin="$(swift build --show-bin-path)"
profdata="$(dirname "$(swift test --show-codecov-path)")/default.profdata"
objects=()
for bundle in "$bin"/*.xctest; do
    objects+=(-object "$bundle/Contents/MacOS/$(basename "$bundle" .xctest)")
done
ignore="^$(pwd)/(\.build|Tests|Sources/TreeSitterScanners)/"

mkdir -p coverage
xcrun llvm-cov report "${objects[@]}" -instr-profile "$profdata" -ignore-filename-regex="$ignore" > coverage/report.txt
xcrun llvm-cov export "${objects[@]}" -instr-profile "$profdata" -ignore-filename-regex="$ignore" -format=lcov > coverage.lcov
scripts/coverage-gate.sh coverage.lcov scripts/coverage-thresholds.txt
