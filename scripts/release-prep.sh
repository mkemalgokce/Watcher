#!/bin/bash
# Prepares the release commit: sets the version Watcher reports (HAR files, MCP) and the bug report placeholder to
# <version>, and regenerates CHANGELOG.md with a section for v<version>. Merge the result, then tag v<version> on it.
# Usage: scripts/release-prep.sh <version>
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?usage: release-prep.sh <version>}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || { echo "version must look like 1.2.3: $version" >&2; exit 1; }
if git rev-parse -q --verify "refs/tags/v$version" > /dev/null; then
    echo "tag v$version already exists" >&2
    exit 1
fi

version_file=Sources/WatcherCore/Model/WatcherVersion.swift
current="$(sed -n 's/.*static let current = "\(.*\)"/\1/p' "$version_file")"
[[ -n "$current" ]] || { echo "no version in $version_file" >&2; exit 1; }

# <file> <text before the version>: every file must still carry the current version, so none is left behind.
files=(
    "$version_file|static let current = \""
    "Tests/WatcherSnapshotTests/__Snapshots__/InterfaceSnapshotTests/theHARExportStaysTheSame.1.txt|\"version\" : \""
    ".github/ISSUE_TEMPLATE/bug_report.yml|placeholder: "
)
for entry in "${files[@]}"; do
    file="${entry%%|*}" prefix="${entry#*|}"
    grep -qF -- "$prefix$current" "$file" || { echo "$file does not carry $current" >&2; exit 1; }
done
for entry in "${files[@]}"; do
    file="${entry%%|*}" prefix="${entry#*|}"
    PREFIX="$prefix" FROM="$current" TO="$version" perl -pi -e 's/\Q$ENV{PREFIX}$ENV{FROM}\E/$ENV{PREFIX}$ENV{TO}/' "$file"
done

git cliff --tag "v$version" -o CHANGELOG.md
