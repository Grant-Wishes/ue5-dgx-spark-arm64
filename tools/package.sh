#!/usr/bin/env bash
# Packages the sample project as a Linux arm64 game, natively on the arm64 host, with Epic's own AutomationTool
# (BuildCookRun: build the game target, cook the content for Vulkan SM6, stage, pak, archive).
# Usage: UE_ENGINE=... tools/package.sh [ARCHIVE_DIR] [extra BuildCookRun arguments...]
# The game then runs with: ARCHIVE_DIR/Linux/<Project>.sh -vulkan
# Epic's Zen server has no arm64 Linux build: the cooker uses the local derived-data cache only, and the project cooks to
# loose files rather than to a Zen store (bUseZenStore=False, written by build.sh in DefaultGame.ini).
set -euo pipefail
. "$(dirname "$0")/env.sh"
out=${1:-$UE_WORK/package}; shift || true
export PATH="$UE_WORK/clang/bin:$PATH" LINUX_MULTIARCH_ROOT="$UE_WORK/cache/linux-sdk"
export UE_PYTHON_DIR="$UE_WORK/cache/third-party/python3" UE_FBX_STUB_DIR="$UE_WORK/cache/fbx-stub"
cd "$UE_ENGINE"
exec Engine/Build/BatchFiles/RunUAT.sh BuildCookRun -project="$UE_PROJECT" -platform=Linux -clientconfig=Development \
  -build -cook -stage -pak -archive -archivedirectory="$out" -nop4 -utf8output -unattended -ubtargs="-NoUBA" \
  -AdditionalCookerOptions="-ddc=NoZenLocalFallback" "$@"
