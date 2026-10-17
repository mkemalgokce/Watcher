#!/bin/bash
# Renders background.svg into background.tiff, holding the 1x and 2x (Retina) images Finder picks between.
# Run after editing the SVG; needs librsvg (brew install librsvg).
set -euo pipefail
cd "$(dirname "$0")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rsvg-convert -w 660 -h 420 background.svg -o "$work/background.png"
rsvg-convert -w 1320 -h 840 background.svg -o "$work/background@2x.png"
tiffutil -cathidpicheck "$work/background.png" "$work/background@2x.png" -out background.tiff
echo "Wrote $(pwd)/background.tiff"
