#!/bin/bash
# Builds Watcher.app and packs it into dist/Watcher-<version>.dmg: a window with the app, an Applications link to drag it
# onto, and tools/dmg/background.tiff behind them. Needs create-dmg (brew install create-dmg).
# Usage: scripts/package-release.sh <version> <build-number>
# Signing: CODESIGN_IDENTITY (a Developer ID Application identity in the keychain) signs the app and the DMG;
# NOTARY_KEY (.p8 contents), NOTARY_KEY_ID and NOTARY_ISSUER_ID then notarize the DMG and staple the ticket.
# REQUIRE_NOTARIZATION=1 refuses to package without all of them, so a release is never shipped unsigned by mistake.
set -euo pipefail
cd "$(dirname "$0")/.."
version="${1:?usage: package-release.sh <version> <build-number>}"
build="${2:?build number required}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || { echo "version must look like 1.2.3: $version" >&2; exit 1; }
[[ "$build" =~ ^[0-9]+$ ]] || { echo "build number must be an integer: $build" >&2; exit 1; }

notarize=false
if [[ -n "${CODESIGN_IDENTITY:-}" && -n "${NOTARY_KEY:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER_ID:-}" ]]; then
  notarize=true
elif [[ "${REQUIRE_NOTARIZATION:-}" == 1 ]]; then
  echo "REQUIRE_NOTARIZATION=1 needs CODESIGN_IDENTITY, NOTARY_KEY, NOTARY_KEY_ID and NOTARY_ISSUER_ID" >&2
  exit 1
fi

out=build
dist=dist
stage="$out/dmg"
dmg="$dist/Watcher-$version.dmg"
rm -rf "$dist" "$stage"
mkdir -p "$dist" "$stage"

APP_VERSION="$version" APP_BUILD="$build" tools/build-app.sh "$out"
cp -R "$out/Watcher.app" "$stage/"
# Icon positions match the arrow drawn in tools/dmg/background.svg.
create-dmg \
  --volname "Watcher $version" \
  --volicon "$out/Watcher.app/Contents/Resources/AppIcon.icns" \
  --background tools/dmg/background.tiff \
  --window-pos 200 120 \
  --window-size 660 420 \
  --icon-size 112 \
  --text-size 13 \
  --icon "Watcher.app" 165 215 \
  --hide-extension "Watcher.app" \
  --app-drop-link 495 215 \
  "$dmg" "$stage" >/dev/null
rm -rf "$stage"

if $notarize; then
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$dmg"
  key="$(mktemp)"
  trap 'rm -f "$key"' EXIT
  printf '%s' "$NOTARY_KEY" > "$key"
  xcrun notarytool submit "$dmg" --key "$key" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
  # stapler fails unless notarization was accepted, so a rejected build stops here.
  xcrun stapler staple "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose "$dmg"
fi
echo "Packaged $dmg"
