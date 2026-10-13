#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mode="${1:-run}"
case "$mode" in run|--verify|--debug|--logs|--telemetry) ;; *) print -u2 'Usage: build_and_run.sh [--verify|--debug|--logs|--telemetry]'; exit 2 ;; esac
pkill -TERM -x FlowGpt || true
Scripts/build-flowgpt.sh
app="$PWD/release/flowgpt/FlowGpt.app"
if [[ "$mode" == --debug ]]; then exec lldb -- "$app/Contents/MacOS/FlowGpt"; fi
/usr/bin/open -n "$app"
case "$mode" in
    --verify) sleep 1; pgrep -x FlowGpt >/dev/null ;;
    --logs|--telemetry) exec /usr/bin/log stream --info --style compact --predicate 'process == "FlowGpt"' ;;
esac
