#!/usr/bin/env bash
# Refreshes the local code graph in graphify-out/ (ignored by git) in the background, so a commit is never held up.
# Does nothing when graphify is not installed (uv tool install graphifyy) or a refresh is already running.
set -euo pipefail

command -v graphify >/dev/null 2>&1 || exit 0
lock=graphify-out/.update.lock
mkdir -p graphify-out
mkdir "$lock" 2>/dev/null || exit 0
(
    trap 'rmdir "$lock"' EXIT
    graphify update . >graphify-out/update.log 2>&1
) </dev/null >/dev/null 2>&1 &
