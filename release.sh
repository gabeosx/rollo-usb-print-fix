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
# stapler uses exit 68 for a CloudKit service failure. Retry that transient
# failure without suppressing invalid signatures, missing files or other errors.
rollo_stapler() {
    local rollo_attempt rollo_status
    for rollo_attempt in 1 2 3 4; do
        if /usr/bin/xcrun stapler "$@"; then return 0; else rollo_status=$?; fi
        if [[ "$rollo_status" -ne 68 || "$rollo_attempt" -eq 4 ]]; then return "$rollo_status"; fi
        echo "Apple ticket service unavailable; retrying stapler $1 (attempt $((rollo_attempt + 1))/4)." >&2
        /bin/sleep "$((rollo_attempt * 5))"
    done
}
for rollo_package in \
    "dist/Rollo-USB-Print-Fix-$rollo_version-signed.pkg" \
    "dist/Remove-Rollo-USB-Print-Fix-$rollo_version-signed.pkg"; do
    /usr/bin/xcrun notarytool submit "$rollo_package" "${rollo_notary_args[@]}" --wait
    rollo_stapler staple "$rollo_package"
    rollo_stapler validate "$rollo_package"
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
rollo_stapler staple "$rollo_app"
rollo_stapler validate "$rollo_app"
/usr/sbin/spctl --assess --type execute --verbose=4 "$rollo_app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$rollo_app" "dist/Rollo-USB-Print-Fix-Setup-$rollo_version-signed.zip"
python3 verify_distribution.py --kind signed
(cd dist && /usr/bin/shasum -a 256 \
  "Rollo-USB-Print-Fix-$rollo_version-signed.pkg" \
  "Remove-Rollo-USB-Print-Fix-$rollo_version-signed.pkg" \
  "Rollo-USB-Print-Fix-Setup-$rollo_version-signed.zip" > SHA256SUMS-signed.txt)
echo 'Signed artifacts verified, notarized and stapled; checksums describe the final downloads.'
