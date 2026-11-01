#!/usr/bin/env bash
#
# Builds Notchi in Release and packages it as a drag-to-install disk image:
#
#   build/Notchi-<version>.dmg
#     ├── Notchi.app
#     ├── Applications -> /Applications
#     └── LICENSE.txt
#
# Usage:
#   scripts/make-dmg.sh [options]
#
# Options:
#   --identity "<name>"   Code signing identity. Default: the project's own
#                         ("Apple Development"). Use a "Developer ID Application"
#                         identity for a DMG other people can open without warnings.
#   --team <id>           Development team for --identity. Default: the project's.
#   --notarize <profile>  Notarize and staple the DMG, using a notarytool keychain
#                         profile (create one with `xcrun notarytool store-credentials`).
#                         Needs a Developer ID identity.
#   --keychain <path>     Keychain holding the notarytool profile, if it isn't in
#                         the search list (CI uses a temporary one).
#   --adhoc               Sign ad hoc instead (no Apple account needed). The DMG
#                         works on this Mac; other Macs must allow it in
#                         System Settings › Privacy & Security.
#   -h, --help            Show this help.

set -euo pipefail

APP_NAME="Notchi"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
STAGING="$BUILD_DIR/dmg-staging"

IDENTITY=""
TEAM=""
NOTARY_PROFILE=""
NOTARY_KEYCHAIN=""
ADHOC=0

usage() { sed -n '2,/^$/s/^# \{0,1\}//p' "$0"; }
die() { echo "error: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity) IDENTITY="${2:?--identity needs a value}"; shift 2 ;;
        --team) TEAM="${2:?--team needs a value}"; shift 2 ;;
        --notarize) NOTARY_PROFILE="${2:?--notarize needs a keychain profile}"; shift 2 ;;
        --keychain) NOTARY_KEYCHAIN="${2:?--keychain needs a path}"; shift 2 ;;
        --adhoc) ADHOC=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1 (see --help)" ;;
    esac
done

[[ "$(uname)" == "Darwin" ]] || die "building a DMG needs macOS"
if [[ $ADHOC -eq 1 && ( -n "$IDENTITY" || -n "$NOTARY_PROFILE" ) ]]; then
    die "--adhoc can't be combined with --identity or --notarize"
fi
if [[ -n "$NOTARY_PROFILE" && "$IDENTITY" != Developer\ ID\ Application* ]]; then
    die "--notarize needs --identity \"Developer ID Application: …\""
fi

# Signing overrides passed to xcodebuild.
SIGN_ARGS=()
if [[ $ADHOC -eq 1 ]]; then
    # Ad hoc signatures have no team ID, so the hardened runtime's library
    # validation would refuse to load the embedded MediaRemoteAdapter framework.
    SIGN_ARGS+=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO)
elif [[ -n "$IDENTITY" ]]; then
    SIGN_ARGS+=(CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual)
    [[ -n "$TEAM" ]] && SIGN_ARGS+=(DEVELOPMENT_TEAM="$TEAM")
    if [[ "$IDENTITY" == Developer\ ID\ Application* ]]; then
        # Notarization needs a secure timestamp and no get-task-allow entitlement.
        SIGN_ARGS+=(OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
    fi
fi

step "Building $APP_NAME (Release)"
xcodebuild \
    -project "$ROOT/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
    clean build \
    | { if command -v xcpretty >/dev/null; then xcpretty; else grep -E '^(\*\*|error:|warning: .*sign)' || true; fi; }

APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
[[ -d "$APP" ]] || die "build failed: $APP not found"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

step "Verifying the app's signature"
codesign --verify --deep --strict --verbose=2 "$APP"

step "Staging the disk image contents"
rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
cp "$ROOT/LICENSE" "$STAGING/LICENSE.txt"

step "Creating $DMG"
RW_DMG="$BUILD_DIR/$APP_NAME-rw.dmg"
rm -f "$RW_DMG" "$DMG"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -ov "$RW_DMG"

# Lay out the Finder window: the app on the left, Applications on the right.
# Finder scripting can fail without a GUI session (e.g. over SSH or in CI);
# the image still works then, it just opens with Finder's default layout.
MOUNT_DIR="$(mktemp -d /tmp/notchi-dmg.XXXXXX)"
hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$MOUNT_DIR" "$RW_DMG"
detach() { hdiutil detach -quiet "$MOUNT_DIR" 2>/dev/null || hdiutil detach -quiet -force "$MOUNT_DIR" || true; }
trap detach EXIT

# Finder may ask for Automation permission and wait forever when nobody is
# there to answer (CI), so give up after a minute.
LAYOUT_SCRIPT="$BUILD_DIR/dmg-layout.applescript"
cat > "$LAYOUT_SCRIPT" <<EOF
tell application "Finder"
    set dmgFolder to (POSIX file "$MOUNT_DIR") as alias
    open dmgFolder
    set w to container window of dmgFolder
    set current view of w to icon view
    set toolbar visible of w to false
    set statusbar visible of w to false
    set bounds of w to {200, 120, 760, 480}
    set opts to icon view options of w
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set position of item "$APP_NAME.app" of dmgFolder to {150, 150}
    set position of item "Applications" of dmgFolder to {410, 150}
    set position of item "LICENSE.txt" of dmgFolder to {280, 300}
    update dmgFolder without registering applications
    delay 1
    close w
end tell
EOF
osascript "$LAYOUT_SCRIPT" >/dev/null &
OSA_PID=$!
( sleep 60; kill "$OSA_PID" 2>/dev/null ) >/dev/null 2>&1 &
WATCHDOG_PID=$!
if ! wait "$OSA_PID"; then
    echo "warning: couldn't arrange the Finder window; using the default layout" >&2
fi
pkill -P "$WATCHDOG_PID" 2>/dev/null || true
kill "$WATCHDOG_PID" 2>/dev/null || true
rm -f "$LAYOUT_SCRIPT"
sync
detach
trap - EXIT
rmdir "$MOUNT_DIR" 2>/dev/null || true

hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW_DMG"
rm -rf "$STAGING"

if [[ -n "$IDENTITY" ]]; then
    step "Signing the disk image"
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
    step "Notarizing (this can take a few minutes)"
    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
    [[ -n "$NOTARY_KEYCHAIN" ]] && NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN")
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

step "Done"
# GitHub Actions: expose the DMG path and version to later steps.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    { echo "dmg=$DMG"; echo "version=$VERSION"; } >> "$GITHUB_OUTPUT"
fi
echo "$DMG"
