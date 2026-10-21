#!/bin/bash
# Writes the Sparkle feed for a release: one item, the disk image, signed with the update key. The app reads the newest
# feed at releases/latest/download/appcast.xml, so each release carries its own copy and the latest one is the feed.
# SPARKLE_PRIVATE_KEY is the exported EdDSA key (generate_keys -x); it goes to sign_update on stdin, never in an argument.
# Usage: scripts/appcast.sh <version> <build-number> <disk-image> <out.xml>
set -euo pipefail
cd "$(dirname "$0")/.."
usage="usage: appcast.sh <version> <build-number> <disk-image> <out.xml>"
version="${1:?$usage}" build="${2:?$usage}" dmg="${3:?$usage}" out="${4:?$usage}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || { echo "version must look like 1.2.3: $version" >&2; exit 1; }
[[ "$build" =~ ^[0-9]+$ ]] || { echo "build number must be an integer: $build" >&2; exit 1; }
[[ -f "$dmg" ]] || { echo "disk image not found: $dmg" >&2; exit 1; }
: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is missing}"

sign_update="${SIGN_UPDATE:-.build/artifacts/sparkle/Sparkle/bin/sign_update}"
signed="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sign_update" --ed-key-file - "$dmg")" || { echo "could not sign $dmg" >&2; exit 1; }
[[ "$signed" == *'sparkle:edSignature="'* ]] || { echo "no signature in the output of sign_update: $signed" >&2; exit 1; }

repo="${GITHUB_REPOSITORY:-mkemalgokce/Watcher}"
tag="v$version"
cat > "$out" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Watcher</title>
    <item>
      <title>Watcher $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/$repo/releases/tag/$tag</sparkle:fullReleaseNotesLink>
      <enclosure url="https://github.com/$repo/releases/download/$tag/$(basename "$dmg")" $signed type="application/octet-stream"/>
    </item>
  </channel>
</rss>
XML
echo "Wrote $out"
