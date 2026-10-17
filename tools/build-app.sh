#!/bin/bash
# Builds Watcher.app (release) so the menu bar shows the app's name and the icon.
# Usage: tools/build-app.sh [output-dir]   (default: ./build)
# APP_VERSION / APP_BUILD set the version shown in About and Finder; CODESIGN_IDENTITY a Developer ID (default: ad hoc).
set -euo pipefail
cd "$(dirname "$0")/.."
out="${1:-build}"
app="$out/Watcher.app"

swift build -c release --product Watcher
bin="$(swift build -c release --product Watcher --show-bin-path)"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/Watcher" "$app/Contents/MacOS/Watcher"
# SwiftPM resource bundles (icon, privacy manifests): Bundle.module looks in Contents/Resources and traps if they are missing.
for bundle in "$bin"/*.bundle; do cp -R "$bundle" "$app/Contents/Resources/"; done
scripts/third-party-notices.sh "$app/Contents/Resources/THIRD_PARTY_NOTICES.md" >/dev/null
# Liquid Glass icon (light, dark, clear, tinted) from the Icon Composer document; AppIcon.icns stays as the pre-macOS 26 fallback.
xcrun actool tools/icon/AppIcon.icon --compile "$app/Contents/Resources" --app-icon AppIcon --platform macosx \
  --minimum-deployment-target 14.0 --output-partial-info-plist "$out/icon-partial.plist" >/dev/null
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Watcher</string>
  <key>CFBundleDisplayName</key><string>Watcher</string>
  <key>CFBundleIdentifier</key><string>dev.watcher.app</string>
  <key>CFBundleExecutable</key><string>Watcher</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIconName</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${APP_VERSION:-1.0}</string>
  <key>CFBundleVersion</key><string>${APP_BUILD:-1}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Mustafa Kemal Gökçe. MIT License.</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Watcher lets phones and tablets on your network send their traffic through it.</string>
</dict></plist>
PLIST
# Ad hoc runs locally; a release is signed with a Developer ID and the hardened runtime, which notarization requires.
identity="${CODESIGN_IDENTITY:--}"
if [[ "$identity" == "-" ]]; then
  codesign --force --deep --sign - "$app" >/dev/null
else
  codesign --force --deep --options runtime --timestamp --sign "$identity" "$app" >/dev/null
fi
echo "Built $app"
