#!/usr/bin/env bash
set -euo pipefail

# Archives a scheme and sends it to App Store Connect.
#
#   script/archive_and_upload.sh GlazeMac
#   script/archive_and_upload.sh            # all three
#
# Signing is left to Xcode: `-allowProvisioningUpdates` asks it to fetch or create
# the Apple Distribution certificate and the store provisioning profile for the
# team. The certificate it makes lives in Xcode's own store, which is why
# `security find-identity` does not list it even after a successful export.
#
# Build numbers must rise. Bump CURRENT_PROJECT_VERSION in project.yml and run
# `xcodegen generate` before uploading again, or App Store Connect rejects the
# package as a duplicate.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EXPORT_OPTIONS="Packaging/ExportOptions-AppStore.plist"

destination_for() {
  case "$1" in
    GlazeMac) printf 'generic/platform=macOS' ;;
    GlazeiOS) printf 'generic/platform=iOS' ;;
    GlazeTV)  printf 'generic/platform=tvOS' ;;
    *) echo "Unknown scheme: $1" >&2; exit 1 ;;
  esac
}

ship() {
  local scheme="$1"
  local archive="dist/archives/$scheme.xcarchive"

  echo "── $scheme: archiving"
  rm -rf "$archive"
  xcodebuild -project Glaze.xcodeproj -scheme "$scheme" -configuration Release \
    -destination "$(destination_for "$scheme")" -archivePath "$archive" \
    archive -allowProvisioningUpdates

  echo "── $scheme: uploading"
  # The dSYM warnings are for VLC's plugins and the ffmpeg tools, which ship as
  # prebuilt binaries. Nothing is wrong; those frames just will not symbolicate.
  xcodebuild -exportArchive -archivePath "$archive" \
    -exportPath "dist/export/$scheme" -exportOptionsPlist "$EXPORT_OPTIONS" \
    -allowProvisioningUpdates
}

mkdir -p dist/archives dist/export

if [[ $# -gt 0 ]]; then
  ship "$1"
else
  for scheme in GlazeMac GlazeiOS GlazeTV; do
    ship "$scheme"
  done
fi

echo
echo "Uploaded. Processing takes a few minutes before the build appears in"
echo "App Store Connect under each platform's version."
