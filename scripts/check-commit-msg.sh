#!/usr/bin/env bash
# Validates a commit message file against Conventional Commits (see CONTRIBUTING.md).
set -euo pipefail

readonly types="feat|fix|perf|refactor|test|docs|build|ci|chore|style|revert"
readonly pattern="^(${types})(\([a-z0-9-]+\))?!?: [a-z0-9](.*[^.])?$"
readonly max_length="${COMMIT_SUBJECT_MAX:-72}"

# Git drops comment lines and leading blank lines, and trims trailing whitespace, before it records the subject.
subject="$(grep -v '^#' "$1" | tr -d '\r' | grep -v '^[[:space:]]*$' | head -n 1 || true)"
subject="${subject%"${subject##*[![:space:]]}"}"

# Messages Git writes itself.
if [[ "$subject" =~ ^(Merge\ |Revert\ \"|fixup!\ |squash!\ ) ]]; then
    exit 0
fi

if [[ ! "$subject" =~ $pattern ]]; then
    echo "Commit subject must look like 'type(scope): lowercase summary' without a trailing period." >&2
    echo "Types: ${types//|/, }. Got: '${subject}'" >&2
    exit 1
fi

if [[ "${#subject}" -gt "$max_length" ]]; then
    echo "Commit subject is ${#subject} characters; keep it at most ${max_length}." >&2
    exit 1
fi
