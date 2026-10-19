#!/usr/bin/env bash
# Table test for scripts/release-prep.sh. It runs a copy in a scratch git repository holding the three files that carry the
# version, with a stub git-cliff on PATH that records how it was called instead of generating a changelog.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/release-prep.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
version_file=Sources/WatcherCore/Model/WatcherVersion.swift
har_snapshot=Tests/WatcherSnapshotTests/__Snapshots__/InterfaceSnapshotTests/theHARExportStaysTheSame.1.txt
bug_report=.github/ISSUE_TEMPLATE/bug_report.yml
failures=0

setup() {
    rm -rf "$workdir/repo" && mkdir -p "$workdir/repo/scripts" "$workdir/bin"
    cd "$workdir/repo"
    mkdir -p "$(dirname "$version_file")" "$(dirname "$har_snapshot")" "$(dirname "$bug_report")"
    printf 'enum WatcherVersion {\n    static let current = "0.1.1"\n}\n' > "$version_file"
    printf '    "creator" : {\n      "name" : "Watcher",\n      "version" : "0.1.1"\n    },\n' > "$har_snapshot"
    printf '      placeholder: 0.1.1\n' > "$bug_report"
    cp "$script" scripts/release-prep.sh
    git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init && git tag v0.1.1
    printf '#!/bin/bash\necho "git-cliff $*" > CHANGELOG.md\n' > "$workdir/bin/git-cliff"
    chmod +x "$workdir/bin/git-cliff"
    cd - > /dev/null
}

# check <expected exit> <expected text> <arguments...>
check() {
    local expected_status="$1" expected_text="$2" output status=0
    shift 2
    setup
    output="$(PATH="$workdir/bin:$PATH" bash "$workdir/repo/scripts/release-prep.sh" "$@" 2>&1)" || status=$?
    if [[ "$status" -ne "$expected_status" || "$output" != *"$expected_text"* ]]; then
        echo "FAIL: $* expected exit $expected_status with '$expected_text'; got exit $status: $output"
        failures=$((failures + 1))
    fi
}

# expect_file <file> <text>: the last run left <text> in <file>
expect_file() {
    if ! grep -qF -- "$2" "$workdir/repo/$1"; then
        echo "FAIL: $1 lacks '$2': $(cat "$workdir/repo/$1")"
        failures=$((failures + 1))
    fi
}

check 1 "usage: release-prep.sh <version>"
check 1 "version must look like 1.2.3: v1.2.3" v1.2.3
check 1 "version must look like 1.2.3: 1.2" 1.2
check 1 "tag v0.1.1 already exists" 0.1.1

check 0 "" 0.2.0
expect_file "$version_file" 'static let current = "0.2.0"'
expect_file "$har_snapshot" '"version" : "0.2.0"'
expect_file "$bug_report" 'placeholder: 0.2.0'
expect_file CHANGELOG.md "git-cliff --tag v0.2.0 -o CHANGELOG.md"

check 0 "" 1.0.0-beta.1
expect_file "$version_file" 'static let current = "1.0.0-beta.1"'

# A file whose version drifted from WatcherVersion.swift is reported, not silently left behind.
setup
sed -i.bak 's/0.1.1/0.0.9/' "$workdir/repo/$bug_report"
status=0
output="$(PATH="$workdir/bin:$PATH" bash "$workdir/repo/scripts/release-prep.sh" 0.2.0 2>&1)" || status=$?
if [[ "$status" -ne 1 || "$output" != *"$bug_report does not carry 0.1.1"* ]]; then
    echo "FAIL: drifted bug report expected exit 1; got exit $status: $output"
    failures=$((failures + 1))
fi

[[ "$failures" -eq 0 ]] && echo "release-prep: all cases pass" || exit 1
