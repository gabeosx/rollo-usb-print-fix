#!/bin/bash
# Requires publisher-owned Developer ID identities and a configured notarytool profile.
set -euo pipefail
cd "$(dirname "$0")"
: "${APPLICATION_IDENTITY:?Set your Developer ID Application identity}"
: "${INSTALLER_IDENTITY:?Set your Developer ID Installer identity}"
: "${NOTARY_PROFILE:?Set a notarytool Keychain profile name}"
./build.sh
rollo_version=$(python3 script/version.py)
rollo_notary_args=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then rollo_notary_args+=(--keychain "$NOTARY_KEYCHAIN"); fi
rollo_app="$PWD/dist/Rollo USB Print Fix.app"
for rollo_package in \
    "dist/Rollo-USB-Print-Fix-$rollo_version-signed.pkg" \
    "dist/Remove-Rollo-USB-Print-Fix-$rollo_version-signed.pkg"; do
    /usr/bin/xcrun notarytool submit "$rollo_package" "${rollo_notary_args[@]}" --wait
    /usr/bin/xcrun stapler staple "$rollo_package"
    /usr/bin/xcrun stapler validate "$rollo_package"
    /usr/sbin/spctl --assess --type install --verbose=4 "$rollo_package"
done
# Stapling changes the embedded package resources. Copy and reseal the app afterward.
/bin/cp "dist/Rollo-USB-Print-Fix-$rollo_version-signed.pkg" "$rollo_app/Contents/Resources/Install.pkg"
/bin/cp "dist/Remove-Rollo-USB-Print-Fix-$rollo_version-signed.pkg" "$rollo_app/Contents/Resources/Remove.pkg"
/usr/bin/codesign --force --sign "$APPLICATION_IDENTITY" --options runtime --timestamp "$rollo_app"
/usr/bin/codesign --verify --strict "$rollo_app"
rollo_upload="$PWD/build/Setup-notary-upload.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$rollo_app" "$rollo_upload"
/usr/bin/xcrun notarytool submit "$rollo_upload" "${rollo_notary_args[@]}" --wait
/usr/bin/xcrun stapler staple "$rollo_app"
/usr/bin/xcrun stapler validate "$rollo_app"
/usr/sbin/spctl --assess --type execute --verbose=4 "$rollo_app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$rollo_app" "dist/Rollo-USB-Print-Fix-Setup-$rollo_version-signed.zip"
python3 verify_distribution.py --kind signed
(cd dist && /usr/bin/shasum -a 256 \
  "Rollo-USB-Print-Fix-$rollo_version-signed.pkg" \
  "Remove-Rollo-USB-Print-Fix-$rollo_version-signed.pkg" \
  "Rollo-USB-Print-Fix-Setup-$rollo_version-signed.zip" > SHA256SUMS-signed.txt)
echo 'Signed artifacts verified, notarized and stapled; checksums describe the final downloads.'
