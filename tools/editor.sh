#!/usr/bin/env bash
# Runs the arm64 Unreal editor built by build.sh: the same HOME/XDG/.NET redirection (the editor's own UnrealBuildTool
# calls find the arm64 .NET), the derived-data cache on local files only (Epic's Zen server has no arm64 Linux build),
# Vulkan.
# Usage: UE_ENGINE=... tools/editor.sh gui|offscreen|cmd [extra editor arguments...]
#   gui       : on the display DISPLAY_NUM (default 3; tools/display/display.sh start first on a headless machine)
#   offscreen : Vulkan with no window (-RenderOffscreen)
#   cmd       : UnrealEditor-Cmd with no GPU (-nullrhi), for commandlets and Python scripts
set -euo pipefail
. "$(dirname "$0")/env.sh"
mode=${1:-gui}; shift || true
log=${LOG:-$UE_LOGS/editor.log}
common=(-ddc=NoZenLocalFallback -LocalDataCachePath="$UE_WORK/cache/ddc" -nosplash -NoLoadingScreen -ABSLOG="$log")
case "$mode" in
  gui)       export DISPLAY=${DISPLAY:-:${DISPLAY_NUM:-3}} SDL_VIDEODRIVER=x11
             exec "$UE_ENGINE/Engine/Binaries/Linux/UnrealEditor" "$UE_PROJECT" -vulkan "${common[@]}" "$@" ;;
  offscreen) exec "$UE_ENGINE/Engine/Binaries/Linux/UnrealEditor" "$UE_PROJECT" -vulkan -RenderOffscreen -unattended "${common[@]}" "$@" ;;
  cmd)       exec "$UE_ENGINE/Engine/Binaries/Linux/UnrealEditor-Cmd" "$UE_PROJECT" -nullrhi -unattended "${common[@]}" "$@" ;;
  *)         echo "usage: editor.sh gui|offscreen|cmd [editor arguments...]" >&2; exit 2 ;;
esac
