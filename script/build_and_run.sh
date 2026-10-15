#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
rollo_mode="${1:-run}"
case "$rollo_mode" in run|--verify|--logs|--telemetry|--debug) ;; *) echo 'Use run, --verify, --logs, --telemetry or --debug.' >&2; exit 2;; esac
/usr/bin/pkill -x RolloPacingSetup >/dev/null 2>&1 || true
./build.sh
rollo_app="$PWD/dist/Rollo USB Print Fix.app"
if [[ "$rollo_mode" == --debug ]]; then
    /usr/bin/xcrun lldb -- "$rollo_app/Contents/MacOS/RolloPacingSetup"
else
    /usr/bin/open -n "$rollo_app"
    case "$rollo_mode" in
        --verify) /bin/sleep 1; /usr/bin/pgrep -x RolloPacingSetup >/dev/null ;;
        --logs|--telemetry) /usr/bin/log stream --info --style compact --predicate 'process == "RolloPacingSetup"' ;;
    esac
fi
