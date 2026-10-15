#!/bin/bash
set -euo pipefail
umask 022
cd "$(dirname "$0")"
rollo_version=$(python3 script/version.py)
rollo_bundle_version=${rollo_version%%-*}
rollo_build_number=${BUILD_NUMBER:-1}
[[ "$rollo_build_number" =~ ^[1-9][0-9]*$ ]] || { echo 'BUILD_NUMBER must be a positive integer.' >&2; exit 1; }
rollo_build="$PWD/build"
rollo_dist="$PWD/dist"
if [[ -n "${APPLICATION_IDENTITY:-}" || -n "${INSTALLER_IDENTITY:-}" ]]; then
    : "${APPLICATION_IDENTITY:?Set both signing identities}"
    : "${INSTALLER_IDENTITY:?Set both signing identities}"
    rollo_kind=signed
else
    rollo_kind=unsigned-preview
fi
/bin/mkdir -p "$rollo_build/arm64" "$rollo_build/x86_64" "$rollo_dist"
/usr/bin/xcrun swiftc Sources/Repair.swift Tests/Tests.swift -o "$rollo_build/tests"
"$rollo_build/tests" | /usr/bin/tee "$rollo_build/test-results.txt"
/usr/bin/xcrun swiftc -parse-as-library Tests/InstallerChecks.swift -o "$rollo_build/installer-check-tests"
"$rollo_build/installer-check-tests" | /usr/bin/tee "$rollo_build/installer-check-results.txt"
for rollo_arch in arm64 x86_64; do
    /usr/bin/xcrun clang -arch "$rollo_arch" -mmacosx-version-min=13.0 -O2 -Wall -Wextra -Werror \
      Sources/filter.c -lcups -o "$rollo_build/$rollo_arch/rastertorollo-paced"
    /usr/bin/xcrun swiftc -target "$rollo_arch-apple-macos13.0" -O -whole-module-optimization \
      Sources/Repair.swift Sources/main.swift -o "$rollo_build/$rollo_arch/rollo-pacing"
    /usr/bin/xcrun swiftc -target "$rollo_arch-apple-macos13.0" -O -whole-module-optimization -parse-as-library \
      Sources/Repair.swift Sources/Assistant.swift -o "$rollo_build/$rollo_arch/RolloPacingSetup"
done
for rollo_binary in rollo-pacing rastertorollo-paced RolloPacingSetup; do
    /usr/bin/lipo -create "$rollo_build/arm64/$rollo_binary" "$rollo_build/x86_64/$rollo_binary" -output "$rollo_build/$rollo_binary"
    /usr/bin/codesign --force --sign "${APPLICATION_IDENTITY:--}" --options runtime \
      ${APPLICATION_IDENTITY:+--timestamp} "$rollo_build/$rollo_binary"
    /usr/bin/codesign --verify --strict "$rollo_build/$rollo_binary"
done
# A fresh staging tree avoids packaging unrelated files or local diagnostic data.
rollo_stage=$(/usr/bin/mktemp -d "$rollo_build/stage.XXXXXX")
trap '/bin/rm -rf "$rollo_stage"' EXIT
rollo_support="$rollo_stage/root/Library/Application Support/Rollo USB Pacing"
/bin/mkdir -p "$rollo_support" "$rollo_stage/root/Library/Printers/RolloPacing" \
  "$rollo_stage/install-scripts" "$rollo_stage/uninstall-scripts" "$rollo_stage/resources"
/usr/bin/install -m 755 "$rollo_build/rollo-pacing" "$rollo_support/rollo-pacing"
/usr/bin/install -m 755 "$rollo_build/rastertorollo-paced" "$rollo_stage/root/Library/Printers/RolloPacing/rastertorollo-paced"
/usr/bin/install -m 644 README.md LICENSE docs/ADMINISTRATORS.md "$rollo_support/"
/usr/bin/install -m 755 Packaging/preinstall "$rollo_stage/install-scripts/preinstall"
/usr/bin/install -m 755 Packaging/postinstall "$rollo_stage/install-scripts/postinstall"
/usr/bin/install -m 755 Packaging/uninstall-postinstall "$rollo_stage/uninstall-scripts/postinstall"
/usr/bin/install -m 755 "$rollo_build/rollo-pacing" "$rollo_stage/install-scripts/rollo-pacing"
/usr/bin/install -m 755 "$rollo_build/rollo-pacing" "$rollo_stage/uninstall-scripts/rollo-pacing"
/bin/cp Packaging/Resources/*.html "$rollo_stage/resources/"
/usr/bin/sed "s/@VERSION@/$rollo_version/g" Packaging/Distribution.xml > "$rollo_stage/Distribution.xml"
/usr/bin/sed "s/@VERSION@/$rollo_version/g" Packaging/Uninstall.xml > "$rollo_stage/Uninstall.xml"
# Avoid inheriting machine-specific extended attributes into distributable files.
/usr/bin/xattr -cr "$rollo_stage"
/usr/bin/pkgbuild --root "$rollo_stage/root" --ownership recommended --scripts "$rollo_stage/install-scripts" \
  --identifier org.rollo-usb-pacing.install --version "$rollo_version" --install-location / "$rollo_stage/install-component.pkg"
/usr/bin/pkgbuild --nopayload --scripts "$rollo_stage/uninstall-scripts" \
  --identifier org.rollo-usb-pacing.uninstall --version "$rollo_version" "$rollo_stage/uninstall-component.pkg"
rollo_product_args=(--resources "$rollo_stage/resources" --package-path "$rollo_stage")
if [[ "$rollo_kind" == signed ]]; then rollo_product_args+=(--sign "$INSTALLER_IDENTITY" --timestamp); fi
/usr/bin/productbuild --distribution "$rollo_stage/Distribution.xml" \
  "${rollo_product_args[@]}" "$rollo_dist/Rollo-USB-Print-Fix-$rollo_version-$rollo_kind.pkg"
/usr/bin/productbuild --distribution "$rollo_stage/Uninstall.xml" \
  "${rollo_product_args[@]}" "$rollo_dist/Remove-Rollo-USB-Print-Fix-$rollo_version-$rollo_kind.pkg"
rollo_app="$rollo_dist/Rollo USB Print Fix.app"
/bin/mkdir -p "$rollo_app/Contents/MacOS" "$rollo_app/Contents/Resources"
/usr/bin/install -m 755 "$rollo_build/RolloPacingSetup" "$rollo_app/Contents/MacOS/RolloPacingSetup"
/usr/bin/install -m 644 Packaging/Info.plist "$rollo_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $rollo_bundle_version" "$rollo_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $rollo_build_number" "$rollo_app/Contents/Info.plist"
/bin/cp "$rollo_dist/Rollo-USB-Print-Fix-$rollo_version-$rollo_kind.pkg" "$rollo_app/Contents/Resources/Install.pkg"
/bin/cp "$rollo_dist/Remove-Rollo-USB-Print-Fix-$rollo_version-$rollo_kind.pkg" "$rollo_app/Contents/Resources/Remove.pkg"
/usr/bin/install -m 644 README.md LICENSE docs/ADMINISTRATORS.md "$rollo_app/Contents/Resources/"
/usr/bin/xattr -cr "$rollo_app"
/usr/bin/codesign --force --sign "${APPLICATION_IDENTITY:--}" --options runtime \
  ${APPLICATION_IDENTITY:+--timestamp} "$rollo_app"
/usr/bin/codesign --verify --strict "$rollo_app"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$rollo_app" "$rollo_dist/Rollo-USB-Print-Fix-Setup-$rollo_version-$rollo_kind.zip"
(cd "$rollo_dist" && /usr/bin/shasum -a 256 \
  "Rollo-USB-Print-Fix-$rollo_version-$rollo_kind.pkg" \
  "Remove-Rollo-USB-Print-Fix-$rollo_version-$rollo_kind.pkg" \
  "Rollo-USB-Print-Fix-Setup-$rollo_version-$rollo_kind.zip" > "SHA256SUMS-$rollo_kind.txt")
echo "Built $rollo_kind packages in $rollo_dist. Public binary release requires Developer ID signing, notarization and release qualification."
