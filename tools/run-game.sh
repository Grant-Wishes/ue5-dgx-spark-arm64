#!/usr/bin/env bash
# Runs the game packaged by tools/package.sh and measures it with the engine's own CSV profiler: FRAMES frames are
# captured from the start, then the game is closed (-csvExitOnCompletion did not close it on 5.8) and the frame times
# are summarised, leaving out the first SKIP frames (level loading).
# Usage: tools/run-game.sh PACKAGE_DIR [FRAMES] [SKIP] [extra game arguments...]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
pkg=$1; frames=${2:-2400}; skip=${3:-600}; shift 3 2>/dev/null || shift $#
game=$(ls "$pkg"/Linux/*.sh | head -1)
log=${LOG:-/tmp/ue-game-$USER.log}
export DISPLAY=${DISPLAY:-:3}
# its own process group: <Project>.sh starts the game binary as a child, and the whole group is closed at the end
setsid "$game" -vulkan -windowed -ResX=1920 -ResY=1080 -nosound -csvCaptureFrames="$frames" \
  -ExecCmds="t.MaxFPS 0,r.VSync 0,stat fps,stat unit" "$@" > "$log" 2>&1 &
pid=$!
for _ in $(seq 1200); do   # up to 10 minutes
  grep -aq "Capture Ended. Writing CSV" "$log" && break
  kill -0 "$pid" 2>/dev/null || break
  sleep 0.5
done
sleep 3   # the CSV is written by a background thread
kill -- -"$pid" 2>/dev/null || true; sleep 2; kill -9 -- -"$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true
csv=$(grep -ao "Writing CSV to file : .*\.csv" "$log" | tail -1 | sed 's/.*: //')
[ -n "$csv" ] || { echo "no CSV capture (see $log)" >&2; exit 1; }
python3 "$here/csv-summary.py" "$(dirname "$game")/SparkMH/Binaries/Linux/$csv" "$skip" 2>/dev/null ||
  python3 "$here/csv-summary.py" "$(find "$(dirname "$game")" -path "*Profiling/CSV/$(basename "$csv")" | head -1)" "$skip"
