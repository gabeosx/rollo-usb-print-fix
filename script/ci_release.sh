#!/bin/bash
# GitHub-hosted runners only. Never import publishing keys during PR builds.
set -euo pipefail
set +x
umask 077
cd "$(dirname "$0")/.."
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo 'Use release.sh for local releases.' >&2; exit 1; }
: "${RUNNER_TEMP:?}"
for rollo_required in MACOS_APPLICATION_P12 MACOS_APPLICATION_PASSWORD MACOS_INSTALLER_P12 MACOS_INSTALLER_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_SPECIFIC_PASSWORD; do
    [[ -n "${!rollo_required:-}" ]] || { echo "$rollo_required is not configured in the release environment." >&2; exit 1; }
done
rollo_private=$(/usr/bin/mktemp -d "$RUNNER_TEMP/rollo-signing.XXXXXX")
rollo_keychain="$rollo_private/release.keychain-db"
rollo_keychain_password=$(/usr/bin/openssl rand -hex 24)
rollo_compatible_password=$(/usr/bin/openssl rand -hex 24)
echo "::add-mask::$rollo_keychain_password"
echo "::add-mask::$rollo_compatible_password"
export ROLLO_COMPATIBLE_PASSWORD="$rollo_compatible_password"
rollo_cleanup() {
    /usr/bin/security delete-keychain "$rollo_keychain" >/dev/null 2>&1 || true
    /bin/rm -rf "$rollo_private"
}
trap rollo_cleanup EXIT
/usr/bin/security create-keychain -p "$rollo_keychain_password" "$rollo_keychain"
/usr/bin/security set-keychain-settings -lut 21600 "$rollo_keychain"
/usr/bin/security unlock-keychain -p "$rollo_keychain_password" "$rollo_keychain"
# Apple public intermediate; leaf certificates and private keys come only from secrets.
/usr/bin/curl --fail --silent --show-error --proto '=https' --tlsv1.2 \
  https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer -o "$rollo_private/intermediate.cer"
/usr/bin/security import "$rollo_private/intermediate.cer" -t cert -k "$rollo_keychain" >/dev/null
for rollo_type in APPLICATION INSTALLER; do
    rollo_p12_var="MACOS_${rollo_type}_P12"
    rollo_password_var="MACOS_${rollo_type}_PASSWORD"
    printf '%s' "${!rollo_p12_var}" | /usr/bin/base64 -D > "$rollo_private/input.p12"
    # Normalize modern OpenSSL exports for Apple's Keychain PKCS#12 reader.
    openssl pkcs12 -in "$rollo_private/input.p12" -clcerts -nokeys \
      -passin "env:$rollo_password_var" -out "$rollo_private/cert.pem"
    rollo_identity=$(openssl x509 -in "$rollo_private/cert.pem" -noout -subject -nameopt multiline | \
      /usr/bin/sed -n 's/^[[:space:]]*commonName[[:space:]]*=[[:space:]]*//p')
    if [[ "$rollo_type" == APPLICATION ]]; then
        [[ "$rollo_identity" == "Developer ID Application: "*" ($APPLE_TEAM_ID)" ]] || { echo 'Application certificate type/team mismatch.' >&2; exit 1; }
        export APPLICATION_IDENTITY="$rollo_identity"
    else
        [[ "$rollo_identity" == "Developer ID Installer: "*" ($APPLE_TEAM_ID)" ]] || { echo 'Installer certificate type/team mismatch.' >&2; exit 1; }
        export INSTALLER_IDENTITY="$rollo_identity"
    fi
    openssl pkcs12 -in "$rollo_private/input.p12" -nocerts \
      -passin "env:$rollo_password_var" -passout env:ROLLO_COMPATIBLE_PASSWORD -out "$rollo_private/key.pem"
    openssl pkcs12 -export -in "$rollo_private/cert.pem" -inkey "$rollo_private/key.pem" \
      -passin env:ROLLO_COMPATIBLE_PASSWORD -passout env:ROLLO_COMPATIBLE_PASSWORD \
      -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -out "$rollo_private/compatible.p12"
    /usr/bin/security import "$rollo_private/compatible.p12" -P "$rollo_compatible_password" \
      -T /usr/bin/codesign -T /usr/bin/productbuild -T /usr/bin/productsign -T /usr/bin/security \
      -f pkcs12 -k "$rollo_keychain" >/dev/null
done
/usr/bin/security set-key-partition-list -S apple-tool:,apple: -s -k "$rollo_keychain_password" "$rollo_keychain" >/dev/null
/usr/bin/security list-keychains -d user -s "$rollo_keychain"
/usr/bin/security find-identity -v -p codesigning "$rollo_keychain" | /usr/bin/grep -F "$APPLICATION_IDENTITY" >/dev/null
/usr/bin/security find-certificate -c "$INSTALLER_IDENTITY" "$rollo_keychain" >/dev/null
export NOTARY_PROFILE=rollo-release
export NOTARY_KEYCHAIN="$rollo_keychain"
/usr/bin/xcrun notarytool store-credentials "$NOTARY_PROFILE" --keychain "$rollo_keychain" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" >/dev/null
./release.sh
