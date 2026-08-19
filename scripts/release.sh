#!/usr/bin/env bash
#
# Builds a signed, notarized LazyFlow.dmg that anyone can download and run.
#
#   scripts/release.sh                       # full release: sign + notarize + staple + DMG
#   scripts/release.sh --version 1.1.0       # override the version baked into the build
#   scripts/release.sh --skip-notarize       # local test DMG (NOT distributable)
#
# Requires (see RELEASING.md):
#   * a "Developer ID Application" certificate in the login keychain
#   * a notarytool keychain profile (default name: LazyFlow-Notary)
#
set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────

TEAM_ID="${TEAM_ID:-Q78J7L8TLR}"          # Fanpit Technologies Private Limited
SCHEME="LazyFlow"
APP_NAME="LazyFlow"
PROJECT="LazyFlow.xcodeproj"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-LazyFlow-Notary}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DIST_DIR="$REPO_ROOT/dist"
STAGE_DIR="$BUILD_DIR/dmg-stage"

VERSION=""
BUILD_NUMBER=""
SKIP_NOTARIZE=0

# ── Args ─────────────────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)          VERSION="$2"; shift 2 ;;
    --build)            BUILD_NUMBER="$2"; shift 2 ;;
    --keychain-profile) KEYCHAIN_PROFILE="$2"; shift 2 ;;
    --skip-notarize)    SKIP_NOTARIZE=1; shift ;;
    -h|--help)          sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

cd "$REPO_ROOT"

step() { printf '\n\033[1;34m▶ %s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31m✗ %s\033[0m\n' "$1" >&2; exit 1; }
ok()   { printf '\033[0;32m  ✓ %s\033[0m\n' "$1"; }

# ── Preflight ────────────────────────────────────────────────────────────────

step "Preflight"

SIGN_ID=""
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  if [[ $SKIP_NOTARIZE -eq 1 ]]; then
    echo "  ! No Developer ID certificate — building an UNSIGNED test DMG."
    SIGN_ID=""
  else
    fail "No 'Developer ID Application' certificate in your keychain.

Create one (Account Holder or Admin on team $TEAM_ID):
  Xcode ▸ Settings ▸ Accounts ▸ select the team ▸ Manage Certificates…
  ▸ '+' ▸ Developer ID Application

Then re-run. To produce an unsigned local test DMG meanwhile:
  scripts/release.sh --skip-notarize"
  fi
else
  # Use whichever Developer ID identity actually exists on this machine.
  SIGN_ID="$(security find-identity -v -p codesigning \
             | grep "Developer ID Application" | head -1 \
             | sed -E 's/.*"(.*)"$/\1/')"
  ok "Signing identity: $SIGN_ID"
fi

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
  if ! xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
    fail "No notarytool credentials stored under profile '$KEYCHAIN_PROFILE'.

Create an app-specific password at https://account.apple.com ▸ Sign-In and Security
▸ App-Specific Passwords, then run:

  xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\
      --apple-id \"you@example.com\" \\
      --team-id \"$TEAM_ID\" \\
      --password \"xxxx-xxxx-xxxx-xxxx\""
  fi
  ok "notarytool profile: $KEYCHAIN_PROFILE"
fi

command -v create-dmg >/dev/null || fail "create-dmg not found — brew install create-dmg"
ok "create-dmg present"

# ── Version ──────────────────────────────────────────────────────────────────

step "Version"

VERSION_ARGS=()
if [[ -n "$VERSION" ]]; then
  VERSION_ARGS+=("MARKETING_VERSION=$VERSION")
else
  VERSION="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
             -showBuildSettings 2>/dev/null \
             | awk -F' = ' '/ MARKETING_VERSION /{print $2; exit}')"
fi
if [[ -n "$BUILD_NUMBER" ]]; then
  VERSION_ARGS+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi
[[ -n "$VERSION" ]] || fail "Could not determine MARKETING_VERSION"
ok "Version $VERSION"

DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"

# ── Archive ──────────────────────────────────────────────────────────────────

step "Archiving (Release)"

rm -rf "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"

ARCHIVE_ARGS=(
  -project "$PROJECT" -scheme "$SCHEME" -configuration Release
  -destination 'generic/platform=macOS'
  -archivePath "$ARCHIVE"
)
if [[ -n "$SIGN_ID" ]]; then
  ARCHIVE_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID")
else
  ARCHIVE_ARGS+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="")
fi

xcodebuild "${ARCHIVE_ARGS[@]}" "${VERSION_ARGS[@]}" archive \
  | grep -E '^(\*\*|.*error:)' || true
[[ -d "$ARCHIVE" ]] || fail "Archive failed — see the xcodebuild output above"
ok "Archived"

# ── Export ───────────────────────────────────────────────────────────────────

step "Exporting app"

APP="$EXPORT_DIR/$APP_NAME.app"

if [[ -n "$SIGN_ID" ]]; then
  # Generated here rather than checked in so the team ID can't drift out of sync.
  cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>            <string>developer-id</string>
    <key>teamID</key>            <string>$TEAM_ID</string>
    <key>signingStyle</key>      <string>automatic</string>
    <key>destination</key>       <string>export</string>
</dict>
</plist>
PLIST

  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    | grep -E '^(\*\*|.*error:)' || true
else
  mkdir -p "$EXPORT_DIR"
  cp -R "$ARCHIVE/Products/Applications/$APP_NAME.app" "$EXPORT_DIR/"
fi

[[ -d "$APP" ]] || fail "Export failed — no app at $APP"
ok "Exported $APP"

# ── Re-sign Sparkle's nested helpers ─────────────────────────────────────────

if [[ -n "$SIGN_ID" ]]; then
  step "Re-signing nested helpers"

  # Sparkle ships Autoupdate, Updater.app and two XPC services *ad-hoc signed*.
  # Notarization rejects any ad-hoc signed executable, so they are re-signed with
  # the Developer ID identity here. Signing must run inside-out: nested code first,
  # containing bundle last, otherwise the outer seal is invalidated.
  FW="$APP/Contents/Frameworks/Sparkle.framework"
  if [[ -d "$FW" ]]; then
    # Versions/[A-Z] deliberately matches the real version dir (B) and not the
    # "Current" symlink beside it — globbing both signs everything twice.
    shopt -s nullglob
    NESTED=(
      "$FW"/Versions/[A-Z]/XPCServices/*.xpc
      "$FW"/Versions/[A-Z]/Updater.app
      "$FW"/Versions/[A-Z]/Autoupdate
      "$FW"
    )
    shopt -u nullglob
    for target in "${NESTED[@]}"; do
      codesign --force --sign "$SIGN_ID" --options runtime --timestamp "$target" 2>&1 \
        | grep -v "replacing existing signature" || true
      ok "signed $(basename "$target")"
    done
  fi

  # The outer app is re-sealed last. Entitlements MUST be passed explicitly —
  # re-signing without them silently strips microphone and network access.
  codesign --force --sign "$SIGN_ID" --options runtime --timestamp \
           --entitlements "$REPO_ROOT/LazyFlow/LazyFlow.entitlements" "$APP" 2>&1 \
    | grep -v "replacing existing signature" || true
  ok "re-sealed LazyFlow.app"
fi

# ── Verify signature ─────────────────────────────────────────────────────────

if [[ -n "$SIGN_ID" ]]; then
  step "Verifying signature"

  codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -2
  codesign -dv --verbose=4 "$APP" 2>&1 | grep -E 'Authority=|TeamIdentifier|flags=' | head -4

  # Catch ad-hoc stragglers here rather than after a five-minute notarization round trip.
  ADHOC=0
  while IFS= read -r item; do
    if codesign -d --verbose=2 "$item" 2>&1 | grep -q "adhoc"; then
      echo "  ✗ still ad-hoc: ${item#"$APP"/}"
      ADHOC=1
    fi
  done < <(find "$APP/Contents" \( -name "*.xpc" -o -name "*.app" -o -name "*.framework" \) -print
           find "$APP/Contents/Frameworks" -type f -name "Autoupdate" -print 2>/dev/null)
  [[ $ADHOC -eq 0 ]] || fail "Ad-hoc signed code left in the bundle — notarization would reject it"

  # Entitlements survive the re-seal?
  codesign -d --entitlements - --xml "$APP" 2>/dev/null \
    | plutil -p - 2>/dev/null | grep -q "audio-input" \
    || fail "Microphone entitlement missing after re-signing"

  ok "Signature valid, hardened runtime on, entitlements intact"
fi

# ── Notarize the app ─────────────────────────────────────────────────────────

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
  step "Notarizing app (this takes a few minutes)"
  ZIP="$BUILD_DIR/$APP_NAME.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"

  xcrun notarytool submit "$ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait \
    || fail "Notarization failed. Inspect with:
  xcrun notarytool log <submission-id> --keychain-profile \"$KEYCHAIN_PROFILE\""

  xcrun stapler staple "$APP"
  ok "Notarized and stapled"
fi

# ── Build the DMG ────────────────────────────────────────────────────────────

step "Building DMG"

rm -rf "$STAGE_DIR"; mkdir -p "$STAGE_DIR" "$DIST_DIR"
cp -R "$APP" "$STAGE_DIR/"
rm -f "$DMG_PATH"

VOLICON_ARGS=()
ICNS="$APP/Contents/Resources/AppIcon.icns"
[[ -f "$ICNS" ]] && VOLICON_ARGS=(--volicon "$ICNS")

# create-dmg drives Finder via AppleScript to lay the window out. That needs
# Automation permission and fails on headless machines, so fall back to a plain
# (functional, just unstyled) image rather than losing the release.
if ! create-dmg \
      --volname "$APP_NAME $VERSION" \
      "${VOLICON_ARGS[@]}" \
      --window-pos 200 120 \
      --window-size 640 400 \
      --icon-size 128 \
      --icon "$APP_NAME.app" 160 190 \
      --hide-extension "$APP_NAME.app" \
      --app-drop-link 480 190 \
      --no-internet-enable \
      "$DMG_PATH" "$STAGE_DIR" 2>&1 | tail -5; then
  echo "  ! create-dmg failed (likely Finder automation) — using plain hdiutil"
  rm -f "$DMG_PATH"
  hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE_DIR" \
                 -ov -format UDZO "$DMG_PATH" >/dev/null
fi
[[ -f "$DMG_PATH" ]] || fail "DMG was not created"
ok "Created $DMG_PATH"

# ── Sign, notarize and staple the DMG ────────────────────────────────────────

if [[ -n "$SIGN_ID" ]]; then
  step "Signing DMG"
  codesign --force --sign "$SIGN_ID" --timestamp "$DMG_PATH"
  ok "DMG signed"
fi

if [[ $SKIP_NOTARIZE -eq 0 ]]; then
  step "Notarizing DMG"
  # The DMG is notarized in its own right so Gatekeeper is satisfied by the
  # downloaded disk image itself, not only the app inside it.
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$KEYCHAIN_PROFILE" --wait \
    || fail "DMG notarization failed"
  xcrun stapler staple "$DMG_PATH"
  ok "DMG notarized and stapled"

  step "Gatekeeper check"
  spctl -a -t open --context context:primary-signature -vv "$DMG_PATH" 2>&1 | tail -3
fi

# ── Done ─────────────────────────────────────────────────────────────────────

printf '\n\033[1;32m✓ %s\033[0m\n' "$(basename "$DMG_PATH") — $(du -h "$DMG_PATH" | cut -f1)"
echo "  $DMG_PATH"
if [[ $SKIP_NOTARIZE -eq 1 ]]; then
  printf '\n\033[1;33m  Not notarized — for local testing only. Other Macs will refuse to open it.\033[0m\n'
else
  echo
  echo "  Publish with:"
  echo "    gh release create v$VERSION \"$DMG_PATH\" --title \"LazyFlow $VERSION\" --generate-notes"
fi
