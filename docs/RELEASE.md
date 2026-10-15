# Build and release

## GitHub releases

Push a tag matching `v` plus the repository's `VERSION` file, for example `v0.2.0`. The Release workflow builds universal Apple Silicon/Intel executables, signs the setup app and both packages, notarizes and staples them, and publishes the verified downloads with SHA-256 checksums. A prerelease version such as `0.3.0-rc.1` creates a GitHub prerelease.

```sh
# Update VERSION, commit, and push main before tagging.
git tag v0.2.0
git push origin v0.2.0
```

The workflow also accepts an existing tag through **Actions → Release → Run workflow**. It requires that the exact tagged commit belongs to the default branch and that the tag matches VERSION. Published releases cannot be overwritten. Failed runs can reuse an unpublished draft; a retry verifies its complete asset set before publication.

The downloads are:

- `Rollo-USB-Print-Fix-Setup-VERSION-signed.zip`: setup app with install and removal packages.
- `Rollo-USB-Print-Fix-VERSION-signed.pkg`: standalone installer.
- `Remove-Rollo-USB-Print-Fix-VERSION-signed.pkg`: standalone removal package.
- `SHA256SUMS-signed.txt`: checksums of the final downloads.

### Publisher configuration

Create a GitHub Actions environment named `release`, with these environment secrets:

| Secret | Value |
| --- | --- |
| `MACOS_APPLICATION_P12` | Base64-encoded PKCS#12 containing the publisher's Developer ID Application certificate and private key |
| `MACOS_APPLICATION_PASSWORD` | Password protecting that PKCS#12 |
| `MACOS_INSTALLER_P12` | Base64-encoded PKCS#12 containing the publisher's Developer ID Installer certificate and private key |
| `MACOS_INSTALLER_PASSWORD` | Password protecting that PKCS#12 |
| `APPLE_ID` | Apple account used for notarization |
| `APPLE_TEAM_ID` | Team ID for both signing certificates |
| `APPLE_APP_SPECIFIC_PASSWORD` | Apple app-specific password used by notarytool |

Keep credentials and certificate backups outside the source tree. Use `gh secret set --env release` with stdin or GitHub's secret-entry UI; never put values in workflow YAML, issues or release notes. See [GitHub's secret configuration](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets).

Restrict the release environment to version tags and the default branch. Limit repository write access to trusted maintainers: tagged source executes with publishing credentials. Pull-request builds use a separate workflow without signing secrets. The release job imports keys into a temporary Keychain and deletes it on exit. It derives signing identities from the supplied certificates and checks their team and type. No provisioning profiles or special app entitlements are needed.

## Local development

Use macOS with Xcode Command Line Tools and Python 3:

```sh
./build.sh
python3 Tests/test_filter.py
python3 verify_distribution.py
python3 audit.py
```

The build runs transaction and Installer checks, then creates universal executables targeting macOS 13+. Without signing identities it uses ad-hoc executable signatures and names artifacts `unsigned-preview`. Generated artifacts stay in ignored `build/` and `dist/` directories. `BUILD_NUMBER` may supply a positive numeric app build number.

The package contains the new filter, manager and project documentation. It does not embed the original driver, PPD, customer labels or reverse-engineering tools. The setup app performs read-only checks and opens macOS Installer for privileged changes.

## Local signing and notarization

Install publisher-owned Developer ID Application and Developer ID Installer identities in Keychain, and configure a notarytool credential profile. Then run:

```sh
APPLICATION_IDENTITY='Developer ID Application: YOUR ORGANIZATION (TEAMID)' \
INSTALLER_IDENTITY='Developer ID Installer: YOUR ORGANIZATION (TEAMID)' \
NOTARY_PROFILE=YOUR_PROFILE ./release.sh
```

`release.sh` signs all executables with hardened runtime and secure timestamps, signs both packages, notarizes/staples each package, embeds those packages in the app, reseals the app, notarizes/staples it, and creates the final ZIP. It verifies signatures, Gatekeeper acceptance, package contents and checksums after stapling. `NOTARY_KEYCHAIN` can select a custom Keychain for the notary profile.

Before publishing, verify installation/removal and printing on supported hardware, including fresh browser downloads with quarantine intact. Never instruct users to disable Gatekeeper or strip quarantine. Broader deployment should cover multiple queues, interrupted setup recovery, both CPU architectures, supported macOS versions, long print batches and cancellation. Automated USB byte-delivery checks do not verify physical label output.

Apple references: [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/), [signing for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution), [notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
