#!/usr/bin/env bash
# Archive, cloud-sign and (optionally) upload one build to App Store Connect (decision D14).
#
#   tools/release/release.sh <staging|prod> <upload|validate>
#
# Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (the .p8 file), BUILD_NUMBER.
# The archive is built unsigned; the export signs it with Apple's cloud-managed distribution certificate
# through the App Store Connect API key (Admin role required), so no certificate or profile lives in the repo.
# `validate` checks the .ipa against App Store Connect without uploading it (dry run on PRs).
set -euo pipefail

env_name="${1:?staging|prod}"
mode="${2:?upload|validate}"
: "${ASC_KEY_ID:?}" "${ASC_ISSUER_ID:?}" "${ASC_KEY_PATH:?}" "${BUILD_NUMBER:?}"

case "$env_name" in
  staging) scheme="Delulutopia Staging"; config="Release-Staging"; bundle_id="com.delulutopia.app.test" ;;
  prod)    scheme="Delulutopia";         config="Release-Prod";    bundle_id="com.delulutopia.app" ;;
  *) echo "unknown environment: $env_name" >&2; exit 2 ;;
esac
case "$mode" in upload|validate) ;; *) echo "unknown mode: $mode" >&2; exit 2 ;; esac

root="$(cd "$(dirname "$0")/../.." && pwd)"
out="$root/build/release"
archive="$out/Delulutopia.xcarchive"
rm -rf "$out"; mkdir -p "$out/ipa"

team="$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$root/Configs/Base.xcconfig" | tr -d '[:space:]')"
[ -n "$team" ] || { echo "DEVELOPMENT_TEAM is empty in Configs/Base.xcconfig" >&2; exit 1; }

auth=(-allowProvisioningUpdates
      -authenticationKeyPath "$ASC_KEY_PATH"
      -authenticationKeyID "$ASC_KEY_ID"
      -authenticationKeyIssuerID "$ASC_ISSUER_ID")

echo "::group::Archive $scheme ($config) build $BUILD_NUMBER"
xcodebuild archive \
  -project "$root/Delulutopia.xcodeproj" -scheme "$scheme" -configuration "$config" \
  -destination "generic/platform=iOS" -archivePath "$archive" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" CODE_SIGNING_ALLOWED=NO \
  | xcbeautify
echo "::endgroup::"

# An unsigned archive carries no entitlements, and the export re-signs with the ones it finds in the
# binary. Sign the archived app ad hoc with the project's entitlements (nested code first) so the
# export keeps them; it turns aps-environment development into production for App Store Connect.
entitlements="$root/App/Delulutopia.entitlements"
if [ -f "$entitlements" ]; then
  echo "::group::Embed entitlements in the archive"
  archived_app="$(find "$archive/Products/Applications" -maxdepth 1 -name '*.app' | head -1)"
  find "$archived_app" -depth \( -name '*.framework' -o -name '*.dylib' -o -name '*.appex' \) -print0 |
    while IFS= read -r -d '' nested; do
      # An extension keeps its own entitlements (the Notification Service Extension's keychain group).
      case "$(basename "$nested")" in
        DelulutopiaNotify.appex) ext_entitlements="$root/Notify/DelulutopiaNotify.entitlements" ;;
        # The widgets read the app's session from the same keychain group (iPad Layout WG2).
        DelulutopiaWidgets.appex) ext_entitlements="$root/WidgetsExtension/DelulutopiaWidgets.entitlements" ;;
        *) ext_entitlements="" ;;
      esac
      if [ -n "$ext_entitlements" ] && [ -f "$ext_entitlements" ]; then
        codesign --force --sign - --timestamp=none --entitlements "$ext_entitlements" "$nested"
      else
        codesign --force --sign - --timestamp=none "$nested"
      fi
    done
  codesign --force --sign - --timestamp=none --entitlements "$entitlements" "$archived_app"
  codesign -d --entitlements - --xml "$archived_app" 2>/dev/null | grep -o 'aps-environment' || true
  echo "::endgroup::"
fi

cat > "$out/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>$team</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST

echo "::group::Export (cloud signing)"
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$out/ipa" \
  -exportOptionsPlist "$out/ExportOptions.plist" "${auth[@]}" | xcbeautify
echo "::endgroup::"

ipa="$(find "$out/ipa" -name '*.ipa' | head -1)"
[ -n "$ipa" ] || { echo "no .ipa exported" >&2; exit 1; }
codesign -dvv "$ipa" 2>/dev/null || true
unzip -q -o "$ipa" -d "$out/unzipped"
app="$(find "$out/unzipped/Payload" -maxdepth 1 -name '*.app' | head -1)"
codesign -dvv "$app" 2>&1 | grep -E 'Identifier|Authority|TeamIdentifier' || true
actual_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Info.plist")"
# Push (iOS Build Q6): the signed app must carry aps-environment = production, or APNs refuses
# every token. The archive is unsigned, so this checks that the export added it from the profile.
if grep -q "aps-environment" "$root/App/Delulutopia.entitlements" 2>/dev/null; then
  codesign -d --entitlements - --xml "$app" > "$out/entitlements.plist" 2>/dev/null || true
  aps="$(/usr/libexec/PlistBuddy -c 'Print :aps-environment' "$out/entitlements.plist" 2>/dev/null || true)"
  echo "aps-environment: ${aps:-missing}"
  [ "$aps" = "production" ] || { echo "::error::Exported app has aps-environment '${aps:-missing}', expected production" >&2; exit 1; }
fi
[ "$actual_id" = "$bundle_id" ] || { echo "bundle id $actual_id, expected $bundle_id" >&2; exit 1; }

# altool reads the key from ~/.appstoreconnect/private_keys/AuthKey_<id>.p8
mkdir -p ~/.appstoreconnect/private_keys
cp "$ASC_KEY_PATH" ~/.appstoreconnect/private_keys/"AuthKey_$ASC_KEY_ID.p8"

if [ "$mode" = "upload" ]; then
  echo "::group::Upload to App Store Connect"
  xcrun altool --upload-app --type ios --file "$ipa" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "::endgroup::"
else
  echo "::group::Validate against App Store Connect (no upload)"
  xcrun altool --validate-app --type ios --file "$ipa" --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "::endgroup::"
fi

{
  echo "### $([ "$mode" = upload ] && echo Uploaded || echo Validated): $scheme"
  echo "| | |"; echo "| --- | --- |"
  echo "| Bundle id | \`$actual_id\` |"
  echo "| Version | $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Info.plist") ($BUILD_NUMBER) |"
  echo "| Commit | \`${GITHUB_SHA:-local}\` |"
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"
