#!/bin/bash
# Writes the licence and notice files of every package in Package.resolved, including those of code vendored in their
# Sources (such as llhttp), into one Markdown file. tools/build-app.sh puts it in the app, as the Apache-2.0 and MIT
# licences require of a binary distribution.
# Usage: scripts/third-party-notices.sh <out.md>   (after the packages are resolved)
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:?usage: third-party-notices.sh <out.md>}"
python3 -I - "$out" <<'PY'
import json, pathlib, sys
pins = json.load(open("Package.resolved"))["pins"]
lines = ["# Third-party notices", "", "Watcher includes the following open-source packages. Their licences and notices follow.", ""]
for pin in sorted(pins, key=lambda p: p["identity"]):
    name = pin["location"].rstrip("/").split("/")[-1].removesuffix(".git")
    root = pathlib.Path(".build/checkouts") / name
    if not root.is_dir():
        sys.exit(f"{root} is missing; run swift package resolve first")
    files = sorted(p for p in root.iterdir() if p.is_file() and p.name.upper().startswith(("LICENSE", "NOTICE", "COPYING")))
    sources = root / "Sources"
    if sources.is_dir():
        files += sorted(p for p in sources.rglob("*") if p.is_file() and p.name.upper().startswith(("LICENSE", "COPYING")))
    if not files:
        sys.exit(f"no licence file found for {name}")
    lines += [f"## {name} {pin['state'].get('version', pin['state'].get('revision', ''))}", "", pin["location"], ""]
    for file in files:
        lines += [f"### {file.relative_to(root)}", "", "```", file.read_text(errors="replace").rstrip(), "```", ""]
pathlib.Path(sys.argv[1]).write_text("\n".join(lines))
PY
echo "Wrote $out"
