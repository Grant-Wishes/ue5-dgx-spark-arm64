#!/usr/bin/env bash
# Starts the editor with its job runner (editor_server.py) and waits until the runner is up.
# Usage: UE_ENGINE=... tools/editor-jobs/server.sh gui|offscreen [TIMEOUT_S] [extra editor arguments...]
# Refuses to start beside a CUDA job: on the DGX Spark the GPU and the memory are shared.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
. "$here/../env.sh"
mode=${1:-gui}; t=${2:-3600}; shift 2 2>/dev/null || shift $#
export UE_JOBS_DIR=${UE_JOBS_DIR:-$(dirname "$UE_PROJECT")/Saved/Jobs}
export UE_DISPLAY_SH="$here/../display/display.sh" UE_SHOTS_DIR=${UE_SHOTS_DIR:-$UE_LOGS}   # for jobs that take screenshots
[ -z "$(nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null)" ] || { echo "the GPU is busy with another job: not starting the editor" >&2; exit 3; }
ps -eo args | grep -q "[U]nrealEditor .*editor_server.py" && { echo "editor already running"; exit 0; }
mkdir -p "$UE_JOBS_DIR"; rm -f "$UE_JOBS_DIR/server.json"
setsid nohup "$here/../editor.sh" "$mode" -ExecutePythonScript="$here/editor_server.py" "$@" > "$UE_LOGS/editor.out" 2>&1 < /dev/null &
start=$(date +%s)
while [ $(( $(date +%s) - start )) -lt "$t" ]; do
  [ -f "$UE_JOBS_DIR/server.json" ] && { echo "job runner ready after $(( $(date +%s) - start )) s"; exit 0; }
  ps -eo args | grep -q "[U]nrealEditor .*editor_server.py" || { echo "the editor exited: see $UE_LOGS/editor.log" >&2; exit 1; }
  sleep 5
done
echo "job runner not ready after $t s" >&2; exit 1
