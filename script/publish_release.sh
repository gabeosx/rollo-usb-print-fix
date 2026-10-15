#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${RELEASE_TAG:?}"
: "${RELEASE_COMMIT:?}"
: "${RUNNER_TEMP:?}"
rollo_version=$(python3 script/version.py "$RELEASE_TAG")
test "$(git rev-parse HEAD)" = "$RELEASE_COMMIT"
rollo_names=("Rollo-USB-Print-Fix-$rollo_version-signed.pkg"
  "Remove-Rollo-USB-Print-Fix-$rollo_version-signed.pkg"
  "Rollo-USB-Print-Fix-Setup-$rollo_version-signed.zip" SHA256SUMS-signed.txt)
rollo_release_json="$RUNNER_TEMP/rollo-release.json"
if gh release view "$RELEASE_TAG" --json tagName,isDraft > "$rollo_release_json" 2>/dev/null; then
    python3 - "$rollo_release_json" "$RELEASE_TAG" <<'PY'
import json, sys
release = json.load(open(sys.argv[1]))
assert release['tagName'] == sys.argv[2] and release['isDraft'], 'Published releases cannot be replaced.'
PY
else
    rollo_create_args=("$RELEASE_TAG" --draft --verify-tag --target "$RELEASE_COMMIT"
      --title "Rollo USB Print Fix $rollo_version" --notes-file Packaging/ReleaseNotes.md)
    if [[ "$rollo_version" == *-* ]]; then rollo_create_args+=(--prerelease); fi
    gh release create "${rollo_create_args[@]}"
fi
rollo_paths=()
for rollo_name in "${rollo_names[@]}"; do rollo_paths+=("dist/$rollo_name"); done
gh release upload "$RELEASE_TAG" --clobber "${rollo_paths[@]}"
# A retry may reuse an unpublished draft, but never publish unknown stale assets.
gh release view "$RELEASE_TAG" --json assets > "$rollo_release_json"
python3 - "$rollo_release_json" "${rollo_names[@]}" <<'PY'
import json, sys
assert {x['name'] for x in json.load(open(sys.argv[1]))['assets']} == set(sys.argv[2:]), 'Unexpected release assets.'
PY
rollo_download=$(/usr/bin/mktemp -d "$RUNNER_TEMP/rollo-download.XXXXXX")
trap '/bin/rm -rf "$rollo_download"' EXIT
gh release download "$RELEASE_TAG" --dir "$rollo_download"
for rollo_name in "${rollo_names[@]}"; do /usr/bin/cmp "dist/$rollo_name" "$rollo_download/$rollo_name"; done
(cd "$rollo_download" && /usr/bin/shasum -a 256 -c SHA256SUMS-signed.txt)
gh release edit "$RELEASE_TAG" --draft=false
echo "Published verified downloads for $RELEASE_TAG." >> "$GITHUB_STEP_SUMMARY"
