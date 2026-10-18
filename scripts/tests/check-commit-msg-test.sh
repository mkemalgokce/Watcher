#!/usr/bin/env bash
# Table test for scripts/check-commit-msg.sh.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/check-commit-msg.sh"
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
failures=0

check() {
    local expected="$1" message="$2" file="$workdir/msg" status=0
    printf '%s\n' "$message" > "$file"
    "$script" "$file" > /dev/null 2>&1 || status=$?
    if [[ "$expected" == accept && "$status" -ne 0 ]] || [[ "$expected" == reject && "$status" -eq 0 ]]; then
        echo "FAIL: expected $expected: $message"
        failures=$((failures + 1))
    fi
}

check accept "feat(foundation): add default port resolution"
check accept "fix: handle empty host"
check accept "fix: x"
check reject "fix: ."
check accept "feat(proxy)!: drop http/1.0"
check accept "chore(deps): bump swift-nio to 2.80.0"
check accept "Merge branch 'main' into feat/x"
check accept "Merge pull request #4 from a/b"
check accept "Merge remote-tracking branch 'origin/main'"
check reject "Merge whatever you like here"
check reject "Merged stuff"
check accept 'Revert "feat: x"'
check accept "fixup! feat: x"
check accept "squash! feat: x"
check accept $'# comment from git\nfeat: add x'
check accept $'feat: add x\n\nBody with Capitals and a period.'

check reject $'feat: add x\n\nCo-Authored-By: Someone <a@b.c>'
check reject $'feat: add x\n\nco-authored-by: Someone <a@b.c>'
check reject $'feat: add x\n\nGenerated with a tool'
check reject $'feat: add x\n\nWritten with Claude'
check reject $'feat: add x\n\nAI assisted'
check accept $'feat: add x\n\nMaintain the main chain; said and paid.'
check accept $'feat: add x\n# Co-Authored-By in a git comment'

check reject "add stuff"
check reject "feat: "
check reject "feat:add thing"
check reject "feat: Add thing"
check reject "feat: add thing."
check reject "feature: add thing"
check reject "feat(Proxy): add thing"
check reject "feat(): add thing"
check reject ""
check reject "feat: $(printf 'a%.0s' {1..61})"

check accept "feat: $(printf 'a%.0s' {1..60})"
check accept "feat: $(printf 'a%.0s' {1..60})  "
check accept $'\nfeat: add x'
check accept $'\n\n# comment\nfeat: add x'
check accept "feat: add x "
check accept $'feat: add x\r'
check reject "feat: add x. "
check reject $'feat: add x.\r'
check reject $'\n\n'

# PR titles leave room for the " (#N)" suffix GitHub appends to squash commits.
title="feat: $(printf 'a%.0s' {1..61})"
printf '%s\n' "$title" > "$workdir/title"
if COMMIT_SUBJECT_MAX=66 "$script" "$workdir/title" > /dev/null 2>&1; then
    echo "FAIL: a 67-character title passed with COMMIT_SUBJECT_MAX=66"
    failures=$((failures + 1))
fi
printf '%s\n' "feat: $(printf 'a%.0s' {1..60})" > "$workdir/title"
if ! COMMIT_SUBJECT_MAX=66 "$script" "$workdir/title" > /dev/null 2>&1; then
    echo "FAIL: a 66-character title failed with COMMIT_SUBJECT_MAX=66"
    failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
    echo "$failures case(s) failed"
    exit 1
fi
echo "all cases passed"
