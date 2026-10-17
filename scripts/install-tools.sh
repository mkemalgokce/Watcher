#!/bin/bash
# Installs the pinned SwiftLint and SwiftFormat release binaries into .tools/, checking their SHA-256.
# Prebuilt binaries take seconds; building them from source (as Mint does) takes minutes on every fresh machine.
# To update: change a version and its checksum (shasum -a 256 of the release zip) below.
set -euo pipefail
cd "$(dirname "$0")/.."

install() { # name version url sha256
  local name="$1" version="$2" url="$3" sha="$4" dir=".tools/$1-$2"
  if [[ ! -x "$dir/$name" ]]; then
    local zip
    zip="$(mktemp)"
    curl -fsSL --retry 3 -o "$zip" "$url"
    echo "$sha  $zip" | shasum -a 256 -c --quiet - || { echo "checksum mismatch for $url" >&2; rm -f "$zip"; exit 1; }
    rm -rf "$dir" && mkdir -p "$dir"
    unzip -q -o "$zip" -d "$dir"
    rm -f "$zip"
  fi
  ln -sfn "$name-$version/$name" ".tools/$name"
  echo "$name $version"
}

install swiftlint 0.65.1 \
  https://github.com/realm/SwiftLint/releases/download/0.65.1/portable_swiftlint.zip \
  c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0
install swiftformat 0.63.1 \
  https://github.com/nicklockwood/SwiftFormat/releases/download/0.63.1/swiftformat.zip \
  385ef1a263ba28685157b98c5536b9c9105e124518f28b7ef8a2bee4b167eaeb
