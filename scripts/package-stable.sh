#!/bin/zsh

set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"

required_variables=(
  GITHUBBAR_VERSION
  GITHUBBAR_BUILD_NUMBER
  GITHUBBAR_DEVELOPMENT_TEAM
  GITHUBBAR_SIGNING_IDENTITY
  GITHUBBAR_SPARKLE_PUBLIC_KEY
  GITHUBBAR_SPARKLE_FEED_URL
  GITHUBBAR_DOWNLOAD_URL_PREFIX
)
for variable in $required_variables; do
  if [[ -z "${(P)variable:-}" ]]; then
    print -u2 "Missing required stable-release setting: $variable"
    exit 1
  fi
done

if [[ "$GITHUBBAR_SPARKLE_FEED_URL" != https://* || "$GITHUBBAR_DOWNLOAD_URL_PREFIX" != https://* ]]; then
  print -u2 "Stable Sparkle feed and download URLs must use HTTPS."
  exit 1
fi
if [[ "$GITHUBBAR_SIGNING_IDENTITY" != "Developer ID Application:"* ]]; then
  print -u2 "Stable releases require a Developer ID Application identity."
  exit 1
fi

if ! command -v xcodebuild >/dev/null || ! xcodebuild -version >/dev/null 2>&1; then
  print -u2 "A full Xcode installation is required for stable archives."
  exit 1
fi
if ! security find-identity -v -p codesigning | rg -Fq "$GITHUBBAR_SIGNING_IDENTITY"; then
  print -u2 "The requested Developer ID Application identity is not installed."
  exit 1
fi

build_root="${GITHUBBAR_BUILD_DIR:-$repo_root/.build/stable}"
dist_dir="${GITHUBBAR_DIST_DIR:-$repo_root/dist/stable}"
derived_data="$build_root/DerivedData"
archive_path="$build_root/GitHubBar.xcarchive"
app_path="$archive_path/Products/Applications/GitHubBar.app"
notarization_zip="$build_root/GitHubBar-notarization.zip"
updates_dir="$build_root/updates"
artifact_base="GitHubBar-$GITHUBBAR_VERSION-$GITHUBBAR_BUILD_NUMBER"
final_zip="$dist_dir/$artifact_base.zip"
notary_result="$build_root/notary-result.json"
notary_log="$build_root/notary-log.json"
sparkle_account="${GITHUBBAR_SPARKLE_KEY_ACCOUNT:-com.franciscomoretti.githubbar}"

rm -rf "$build_root"
mkdir -p "$build_root" "$dist_dir" "$updates_dir"

xcodegen generate
xcodebuild \
  -project GitHubBar.xcodeproj \
  -scheme GitHubBar \
  -configuration Stable \
  -derivedDataPath "$derived_data" \
  -archivePath "$archive_path" \
  archive \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  DEVELOPMENT_TEAM="$GITHUBBAR_DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$GITHUBBAR_SIGNING_IDENTITY" \
  MARKETING_VERSION="$GITHUBBAR_VERSION" \
  CURRENT_PROJECT_VERSION="$GITHUBBAR_BUILD_NUMBER" \
  GITHUBBAR_SPARKLE_PUBLIC_KEY="$GITHUBBAR_SPARKLE_PUBLIC_KEY" \
  GITHUBBAR_SPARKLE_FEED_URL="$GITHUBBAR_SPARKLE_FEED_URL"

if [[ ! -d "$app_path" ]]; then
  print -u2 "Stable archive did not contain GitHubBar.app."
  exit 1
fi

lipo "$app_path/Contents/MacOS/GitHubBar" -verify_arch arm64 x86_64
codesign --verify --deep --strict --verbose=2 "$app_path"
if ! codesign -dv --verbose=4 "$app_path" 2>&1 | rg -q "flags=.*runtime"; then
  print -u2 "Stable app is missing the hardened runtime signature flag."
  exit 1
fi

entitlements_file="$build_root/effective-entitlements.plist"
codesign -d --entitlements :- "$app_path" > "$entitlements_file" 2>/dev/null
if plutil -extract com.apple.security.get-task-allow raw -o - "$entitlements_file" >/dev/null 2>&1; then
  print -u2 "Stable app must not contain com.apple.security.get-task-allow."
  exit 1
fi
if [[ "$(plutil -extract SUFeedURL raw -o - "$app_path/Contents/Info.plist")" != "$GITHUBBAR_SPARKLE_FEED_URL" ]]; then
  print -u2 "Stable app feed URL does not match the requested HTTPS appcast."
  exit 1
fi
if [[ "$(plutil -extract SUPublicEDKey raw -o - "$app_path/Contents/Info.plist")" != "$GITHUBBAR_SPARKLE_PUBLIC_KEY" ]]; then
  print -u2 "Stable app does not contain the requested Sparkle public key."
  exit 1
fi

ditto -c -k --sequesterRsrc --keepParent "$app_path" "$notarization_zip"

if [[ -n "${GITHUBBAR_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$notarization_zip" \
    --keychain-profile "$GITHUBBAR_NOTARY_PROFILE" \
    --wait \
    --output-format json > "$notary_result"
elif [[ -n "${GITHUBBAR_NOTARY_KEY_FILE:-}" && -n "${GITHUBBAR_NOTARY_KEY_ID:-}" && -n "${GITHUBBAR_NOTARY_ISSUER_ID:-}" ]]; then
  xcrun notarytool submit "$notarization_zip" \
    --key "$GITHUBBAR_NOTARY_KEY_FILE" \
    --key-id "$GITHUBBAR_NOTARY_KEY_ID" \
    --issuer "$GITHUBBAR_NOTARY_ISSUER_ID" \
    --wait \
    --output-format json > "$notary_result"
else
  print -u2 "Configure a notarytool Keychain profile or Notary API key settings."
  exit 1
fi

notary_status="$(plutil -extract status raw -o - "$notary_result")"
if [[ "$notary_status" != "Accepted" ]]; then
  submission_id="$(plutil -extract id raw -o - "$notary_result" 2>/dev/null || true)"
  if [[ -n "$submission_id" ]]; then
    if [[ -n "${GITHUBBAR_NOTARY_PROFILE:-}" ]]; then
      xcrun notarytool log "$submission_id" --keychain-profile "$GITHUBBAR_NOTARY_PROFILE" "$notary_log" >/dev/null
    else
      xcrun notarytool log "$submission_id" \
        --key "$GITHUBBAR_NOTARY_KEY_FILE" \
        --key-id "$GITHUBBAR_NOTARY_KEY_ID" \
        --issuer "$GITHUBBAR_NOTARY_ISSUER_ID" \
        "$notary_log" >/dev/null
    fi
  fi
  print -u2 "Notarization was not accepted. Inspect $notary_result and $notary_log."
  exit 1
fi

xcrun stapler staple "$app_path"
xcrun stapler validate "$app_path"
spctl --assess --type execute --verbose=4 "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

rm -f "$final_zip" "$final_zip.sha256"
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$final_zip"
cp "$final_zip" "$updates_dir/"
cp docs/releases/stable-release-runbook.md "$updates_dir/$artifact_base.md"

sparkle_bin_dir="${GITHUBBAR_SPARKLE_BIN_DIR:-}"
if [[ -z "$sparkle_bin_dir" ]]; then
  generate_appcast_path="$(find "$derived_data/SourcePackages/artifacts" -type f -name generate_appcast -perm +111 -print -quit 2>/dev/null || true)"
  sparkle_bin_dir="${generate_appcast_path:h}"
fi
if [[ ! -x "$sparkle_bin_dir/generate_appcast" || ! -x "$sparkle_bin_dir/generate_keys" ]]; then
  print -u2 "Could not locate Sparkle's signed release tools."
  exit 1
fi
if ! "$sparkle_bin_dir/generate_keys" --account "$sparkle_account" -p | rg -Fq "$GITHUBBAR_SPARKLE_PUBLIC_KEY"; then
  print -u2 "Sparkle Keychain private key does not match the embedded public key."
  exit 1
fi

"$sparkle_bin_dir/generate_appcast" \
  --account "$sparkle_account" \
  --download-url-prefix "$GITHUBBAR_DOWNLOAD_URL_PREFIX" \
  --link "https://github.com/FranciscoMoretti/GitHubBar" \
  --embed-release-notes \
  --maximum-versions 3 \
  "$updates_dir"

appcast_path="$updates_dir/appcast.xml"
if [[ ! -f "$appcast_path" ]] || ! rg -q 'sparkle:edSignature="[^"]+"' "$appcast_path"; then
  print -u2 "Generated appcast is missing an EdDSA update signature."
  exit 1
fi
if rg -q 'url="http://' "$appcast_path"; then
  print -u2 "Generated appcast contains an insecure update URL."
  exit 1
fi

cp "$appcast_path" "$dist_dir/appcast.xml"
find "$updates_dir" -maxdepth 1 -type f -name '*.delta' -exec cp {} "$dist_dir/" \;
shasum -a 256 "$final_zip" > "$final_zip.sha256"

print "Created notarized stable artifact: $final_zip"
print "Created signed appcast: $dist_dir/appcast.xml"
print "Architectures: $(lipo -archs "$app_path/Contents/MacOS/GitHubBar")"
