#!/usr/bin/env bash

set -euo pipefail

usage() {
    echo "Usage: $0 /path/to/LazyFlow.app [release-tag]" >&2
    echo "Example: $0 build/export/LazyFlow.app v1.1.0" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 64
fi

app_path="$1"
if [[ ! -d "$app_path" || ! -f "$app_path/Contents/Info.plist" ]]; then
    echo "error: expected an exported .app bundle: $app_path" >&2
    exit 66
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
info_plist="$app_path/Contents/Info.plist"
bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$info_plist")"
version="$(plutil -extract CFBundleShortVersionString raw -o - "$info_plist")"
build_number="$(plutil -extract CFBundleVersion raw -o - "$info_plist")"
release_tag="${2:-v$version}"
expected_team_id="${LAZYFLOW_TEAM_ID:-Q78J7L8TLR}"

if [[ "$bundle_id" != "com.fanpit.LazyFlow" ]]; then
    echo "error: unexpected bundle identifier: $bundle_id" >&2
    exit 65
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "error: GitHub CLI (gh) is required to publish the release" >&2
    exit 69
fi

codesign --verify --deep --strict --verbose=2 "$app_path"

signature_details="$(codesign --display --verbose=4 "$app_path" 2>&1)"
authority="$(printf '%s\n' "$signature_details" | sed -n 's/^Authority=//p' | head -n 1)"
team_id="$(printf '%s\n' "$signature_details" | sed -n 's/^TeamIdentifier=//p' | head -n 1)"

if [[ "$authority" != Developer\ ID\ Application:* ]]; then
    echo "error: release must be signed with Developer ID Application; found: ${authority:-none}" >&2
    exit 65
fi

if [[ "$team_id" != "$expected_team_id" ]]; then
    echo "error: expected signing team $expected_team_id; found: ${team_id:-none}" >&2
    exit 65
fi

if ! printf '%s\n' "$signature_details" | grep -q 'runtime'; then
    echo "error: hardened runtime is not enabled on the exported app" >&2
    exit 65
fi

if ! xcrun stapler validate "$app_path"; then
    echo "error: the app does not contain a valid notarization ticket" >&2
    exit 65
fi

if ! spctl --assess --type execute --verbose=4 "$app_path"; then
    echo "error: Gatekeeper rejected the exported app" >&2
    exit 65
fi

release_dir="$(mktemp -d "${TMPDIR:-/tmp}/lazyflow-release.XXXXXX")"
trap 'rm -rf "$release_dir"' EXIT

archive_name="LazyFlow-$version-$build_number.zip"
archive_path="$release_dir/$archive_name"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"

sparkle_tools_dir="${SPARKLE_TOOLS_DIR:-}"
if [[ -z "$sparkle_tools_dir" ]]; then
    source_packages_dir="$repo_root/build/SourcePackages"
    derived_data_dir="$repo_root/build/DerivedData"
    xcodebuild_bin="${XCODEBUILD:-xcodebuild}"

    if ! "$xcodebuild_bin" -version >/dev/null 2>&1; then
        beta_xcodebuild="/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild"
        if [[ -x "$beta_xcodebuild" ]]; then
            xcodebuild_bin="$beta_xcodebuild"
        else
            echo "error: xcodebuild is unavailable; set XCODEBUILD to its full path" >&2
            exit 69
        fi
    fi

    "$xcodebuild_bin" \
        -resolvePackageDependencies \
        -project "$repo_root/LazyFlow.xcodeproj" \
        -scheme LazyFlow \
        -derivedDataPath "$derived_data_dir" \
        -clonedSourcePackagesDirPath "$source_packages_dir"

    sparkle_tools_dir="$source_packages_dir/artifacts/sparkle/Sparkle/bin"
fi

generate_appcast="$sparkle_tools_dir/generate_appcast"
if [[ ! -x "$generate_appcast" ]]; then
    echo "error: Sparkle generate_appcast was not found at $generate_appcast" >&2
    echo "Set SPARKLE_TOOLS_DIR to the Sparkle bin directory and retry." >&2
    exit 69
fi

download_prefix="https://github.com/sanjaibalajee/LazyFlow/releases/download/$release_tag/"
"$generate_appcast" \
    --account com.fanpit.LazyFlow \
    --download-url-prefix "$download_prefix" \
    --link "https://github.com/sanjaibalajee/LazyFlow" \
    --maximum-versions 1 \
    -o "$release_dir/appcast.xml" \
    "$release_dir"

xmllint --noout "$release_dir/appcast.xml"

if gh release view "$release_tag" --repo sanjaibalajee/LazyFlow >/dev/null 2>&1; then
    echo "error: GitHub release $release_tag already exists" >&2
    exit 73
fi

gh release create "$release_tag" \
    "$archive_path" \
    "$release_dir/appcast.xml" \
    --repo sanjaibalajee/LazyFlow \
    --target main \
    --title "LazyFlow $version" \
    --generate-notes

echo "Published LazyFlow $version (build $build_number) as $release_tag."
echo "Update feed: https://github.com/sanjaibalajee/LazyFlow/releases/latest/download/appcast.xml"
