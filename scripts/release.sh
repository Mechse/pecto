#!/usr/bin/env bash
#
# Builds Pecto for release and packages it as a .dmg in dist/.
#
# Ad-hoc (default, no Apple Developer account needed):
#     ./scripts/release.sh
#   Produces a working but *unnotarized* .dmg. macOS quarantines it on
#   download — testers must approve it in System Settings → Privacy & Security.
#
# Signed + notarized (once a Developer ID certificate exists):
#     DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#     NOTARY_PROFILE=pecto-notary \
#     ./scripts/release.sh
#   Create NOTARY_PROFILE once with:
#     xcrun notarytool store-credentials pecto-notary \
#       --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
#
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)
DERIVED="$ROOT/build/dd"
DIST="$ROOT/dist"
APP_NAME="Pecto"

DEVELOPER_ID="${DEVELOPER_ID:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

# --- version ---------------------------------------------------------------
# MARKETING_VERSION in project.yml is the single source of truth.
VERSION=$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
if [[ -z "$VERSION" ]]; then
  echo "error: could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi
echo "==> Building $APP_NAME $VERSION"

# --- build -----------------------------------------------------------------
command -v xcodegen >/dev/null || { echo "error: xcodegen not installed" >&2; exit 1; }
xcodegen generate

rm -rf "$DERIVED" "$DIST"
mkdir -p "$DIST"

# Hardened runtime is required for notarization, so turn it on only when we
# are actually signing with a real identity — it is off for ad-hoc/dev builds.
HARDENED=NO
[[ -n "$DEVELOPER_ID" ]] && HARDENED=YES

xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  ENABLE_HARDENED_RUNTIME=$HARDENED \
  build

APP="$DERIVED/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "error: build produced no app at $APP" >&2; exit 1; }

# --- sign ------------------------------------------------------------------
if [[ -n "$DEVELOPER_ID" ]]; then
  echo "==> Signing with: $DEVELOPER_ID"
  codesign --force --deep --options runtime --timestamp \
    --sign "$DEVELOPER_ID" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  echo "==> Ad-hoc signing (no DEVELOPER_ID set — this build will NOT be notarized)"
  codesign --force --deep --sign - "$APP"
fi

# --- package ---------------------------------------------------------------
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

DMG="$DIST/$APP_NAME-$VERSION.dmg"
echo "==> Packaging $DMG"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

# --- notarize --------------------------------------------------------------
if [[ -n "$DEVELOPER_ID" && -n "$NOTARY_PROFILE" ]]; then
  echo "==> Submitting to Apple for notarization (this can take a few minutes)"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  echo "==> Notarized and stapled"
elif [[ -n "$DEVELOPER_ID" ]]; then
  echo "==> Signed but NOT notarized (set NOTARY_PROFILE to notarize)"
fi

echo
echo "Done: $DMG"
shasum -a 256 "$DMG"
