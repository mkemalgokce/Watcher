#!/usr/bin/env bash
# Validates a commit message file against Conventional Commits (see CONTRIBUTING.md).
set -euo pipefail

readonly types="feat|fix|perf|refactor|test|docs|build|ci|chore|style|revert"
readonly pattern="^(${types})(\([a-z0-9-]+\))?!?: [a-z0-9](.*[^.])?$"
readonly max_length="${COMMIT_SUBJECT_MAX:-66}"

# `git commit -v` appends the diff below a scissors line; Git ignores it, and so does this check.
message="$(sed '/^# -* >8 -*$/,$d' "$1")"

# Git drops comment lines and leading blank lines, and trims trailing whitespace, before it records the subject.
subject="$(printf '%s\n' "$message" | grep -v '^#' | tr -d '\r' | grep -v '^[[:space:]]*$' | head -n 1 || true)"
subject="${subject%"${subject##*[![:space:]]}"}"

# Messages Git writes itself.
if [[ "$subject" =~ ^(Merge\ (branch|tag|commit|pull\ request|remote-tracking)\ |Revert\ \"|fixup!\ |squash!\ ) ]]; then
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

# The history carries no tool or co-author attribution.
if printf '%s\n' "$message" | grep -v '^#' | grep -qiE '^co-authored-by:|claude|anthropic|copilot|chatgpt|openai|(^|[^[:alnum:]])AI([^[:alnum:]]|$)'; then
    echo "Commit message must not carry a Co-Authored-By trailer or an AI attribution." >&2
    exit 1
fi
