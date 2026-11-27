#!/usr/bin/env bash
# Builds the Unreal Engine 5.8 editor natively on Linux ARM64 (NVIDIA DGX Spark / GB10), from a checkout of the
# dgx-spark-arm64 branch of the fork (Epic's GitHub network; the engine patches are commits there, see README.md).
#
# Epic ships no Linux ARM64 editor and its Linux toolchain and many third-party binaries are x86_64 only. This script:
#   toolchain : downloads (pinned, checksummed) .NET 10.0.404, LLVM clang 20.1.8 (the only major UE 5.8 accepts),
#               Intel ISPC 1.24.0 and the public CEF 147 build, all for linux-arm64
#   deps      : builds GitDependencies for arm64 and fetches Epic's binary dependencies (Linux only, about 22 GB)
#   thirdparty: lays out an Epic-style toolchain folder around clang 20 + libc++, builds the x86-only third-party
#               libraries for aarch64 from the sources in the engine tree (scripts/third_party_arm64.sh)
#   uba       : builds UnrealBuildAccelerator's host library for arm64 (UBT 5.8 runs every action through it)
#   build     : UnrealEditor + ShaderCompileWorker + EpicWebHelper for the sample project (all default engine plugins,
#               plus MetaHuman, the MetaHuman Creator, Blackmagic, NDI and Epic's MCP server), then the
#               Binaries/LinuxArm64 links the engine looks for
#   all       : every step above, in order (the default)
# Each step skips work that is already done. Nothing is written to $HOME: caches live under the work folder.
#
# Usage: ./build.sh --engine PATH [--work PATH] [--project PATH] [--jobs N] [--min-free-gib N] [step...]
#   --engine       the engine checkout (dgx-spark-arm64 branch)
#   --work         downloads, toolchains, caches (default: <engine>/../ue-arm64-work)
#   --project      the sample project to create and build (default: <work>/SparkMH/SparkMH.uproject)
#   --jobs         parallel compile jobs (default: number of CPUs)
#   --min-free-gib pause the build (SIGSTOP) while available memory is under this, resume 5 GiB above (default 8)
# Optional: NDI_SDK_DIR=/path/to/"NDI SDK for Linux" (unpacked, its licence accepted by you) puts the SDK's aarch64
# libndi where the NDIMedia plugin loads it; without it NDI is built but has no runtime.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"

DOTNET_VERSION=10.0.404
DOTNET_SHA512=3533a3869da219cac45c567aadac3d8e96cdf1c6a04fe1c1d5fdeefea5d45af8424488f0144730d11b4a751f7ad546fb11e4c2b2725cd8401efee726711f8f11
LLVM_VERSION=20.1.8                     # Engine/Config/Linux/Linux_SDK.json: v26_clang-20.1.8
LLVM_SHA256=b855cc17d935fdd83da82206b7a7cfc680095efd1e9e8182c4a05e761958bef8
ISPC_VERSION=1.24.0                     # the version Epic bundles for x86_64
ISPC_SHA256=890ad5f31581091bf4ae9f235a7bb6fd9cabcbd6cf1670104ad61f1ad2da4c76
CEF_ARM64=cef_binary_147.0.5+g68529a5+chromium-147.0.7727.49_linuxarm64_beta_minimal.tar.bz2   # same CEF commit as UE 5.8's 147.1.5
CEF_ARM64_SHA1=5d19f7fd3e8850570cf6d2bcbe4beadbbb7cc176                                         # from cef-builds.spotifycdn.com/index.json
CEF_DIR_VERSION=147.0.5+g68529a5+chromium-147.0.7727.49

src="" work="" project="" jobs=$(nproc) min_free=8 steps=()
while [ $# -gt 0 ]; do
  case "$1" in
    --engine) src=$(cd "$2" && pwd); shift 2 ;;
    --work) mkdir -p "$2"; work=$(cd "$2" && pwd); shift 2 ;;
    --project) project=$2; shift 2 ;;
    --jobs) jobs=$2; shift 2 ;;
    --min-free-gib) min_free=$2; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) steps+=("$1"); shift ;;
  esac
done
[ -n "$src" ] || { echo "--engine is required (see --help)" >&2; exit 2; }
[ "$(uname -m)" = aarch64 ] || { echo "this script builds on an aarch64 Linux host" >&2; exit 2; }
[ ${#steps[@]} -gt 0 ] || steps=(all)
work=${work:-$(cd "$src/.." && pwd)/ue-arm64-work}
project=${project:-$work/SparkMH/SparkMH.uproject}
mkdir -p "$work"

# The engine tree must be the patched branch: every patch comment carries the marker below.
grep -q "DGX Spark" "$src/Engine/Source/Programs/UnrealBuildTool/Platform/Linux/UEBuildLinux.cs" 2>/dev/null || {
  echo "$src is not the dgx-spark-arm64 branch of the fork (see README.md: 'Getting the engine source')" >&2; exit 2; }

downloads="$work/downloads"; cache="$work/cache"
dotnet_dir="$work/dotnet"; clang_dir="$work/clang"
tc="$cache/linux-sdk/aarch64-unknown-linux-gnueabi"
mkdir -p "$downloads" "$cache"

# Everything the engine's own scripts would put in HOME goes under the work folder (UBA writes ~/.epic, .NET
# ~/.dotnet, AutomationTool its logs). tools/editor.sh sets the same variables to run the editor.
export HOME="$cache/home" XDG_CONFIG_HOME="$cache/xdg-config" XDG_DATA_HOME="$cache/xdg-data" XDG_CACHE_HOME="$cache/xdg-cache"
mkdir -p "$HOME"
export DOTNET_ROOT="$dotnet_dir" PATH="$dotnet_dir:$PATH" UE_USE_SYSTEM_DOTNET=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 DOTNET_CLI_HOME="$cache/dotnet-home" NUGET_PACKAGES="$cache/nuget"
export UE_GITDEPS="$cache/gitdeps" UE_LOCAL_DATA_CACHE_PATH="$cache/ddc"

fetch() {   # URL FILE ALGO SUM
  [ -f "$2" ] && echo "$4  $2" | "$3sum" -c --quiet - 2>/dev/null && return 0
  curl -fsSL -C - -o "$2" "$1"
  echo "$4  $2" | "$3sum" -c --quiet -
}

step_toolchain() {
  local f
  f="dotnet-sdk-$DOTNET_VERSION-linux-arm64.tar.gz"
  if [ ! -x "$dotnet_dir/dotnet" ]; then
    fetch "https://builds.dotnet.microsoft.com/dotnet/Sdk/$DOTNET_VERSION/$f" "$downloads/$f" sha512 "$DOTNET_SHA512"
    rm -rf "$dotnet_dir.tmp"; mkdir -p "$dotnet_dir.tmp"; tar -xzf "$downloads/$f" -C "$dotnet_dir.tmp"; mv "$dotnet_dir.tmp" "$dotnet_dir"
  fi
  f="LLVM-$LLVM_VERSION-Linux-ARM64.tar.xz"
  if [ ! -x "$clang_dir/bin/clang++" ]; then
    fetch "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION/$f" "$downloads/$f" sha256 "$LLVM_SHA256"
    rm -rf "$clang_dir.tmp"; mkdir -p "$clang_dir.tmp"; tar -xJf "$downloads/$f" -C "$clang_dir.tmp" --strip-components=1; mv "$clang_dir.tmp" "$clang_dir"
  fi
  # ISPC: Intel's aarch64 build, where the branch makes UBT look on an arm64 host (bin/LinuxArm64)
  f="ispc-v$ISPC_VERSION-linux.aarch64.tar.gz"
  local ispc="$src/Engine/Source/ThirdParty/Intel/ISPC/bin/LinuxArm64"
  if ! { [ -x "$ispc/ispc" ] && "$ispc/ispc" --version | grep -q " $ISPC_VERSION "; }; then
    fetch "https://github.com/ispc/ispc/releases/download/v$ISPC_VERSION/$f" "$downloads/$f" sha256 "$ISPC_SHA256"
    mkdir -p "$ispc"; tar -xzf "$downloads/$f" -C "$ispc" --strip-components=2 "ispc-v$ISPC_VERSION-linux.aarch64/bin/ispc"
  fi
  fetch "https://cef-builds.spotifycdn.com/${CEF_ARM64//+/%2B}" "$downloads/$CEF_ARM64" sha1 "$CEF_ARM64_SHA1"
  "$dotnet_dir/dotnet" --version; "$clang_dir/bin/clang++" --version | head -1; "$ispc/ispc" --version | head -1
}

# Platforms never built here: their binaries stay on Epic's CDN (91 GB of files in all, about 22 GB of packs left).
GITDEPS_EXCLUDE=(Win64 Win32 Mac Android IOS TVOS HoloLens VisionOS osx64 osx Windows WinArm64 Win64Arm64 XboxOne PS4 PS5
                 Switch GDK WinGDK arm64-v8a armeabi-v7a x86_64-apple-darwin Apple macOS iOS)

step_deps() {
  local gd="$src/Engine/Binaries/DotNET/GitDependencies/linux-arm64" args=() x
  [ -f "$work/.deps-done" ] && return 0
  # Epic ships GitDependencies for linux-x64 only: built from its source for arm64 (the branch fixes its stat() call)
  [ -x "$gd/GitDependencies" ] || dotnet publish "$src/Engine/Source/Programs/GitDependencies/GitDependencies.csproj" \
    -c Release -r linux-arm64 --self-contained false -o "$gd" -nologo
  for x in "${GITDEPS_EXCLUDE[@]}"; do args+=("--exclude=$x"); done
  (cd "$src" && "$gd/GitDependencies" --force --cache="$cache/gitdeps" "${args[@]}")
  # the exclusions also drop tool files in folders named like a platform (AutomationTool/IOS/...): fetched back
  python3 -B "$here/scripts/gitdeps_tools.py" "$src" "${GITDEPS_EXCLUDE[@]}"
  touch "$work/.deps-done"
}

# Epic's Linux toolchain is clang 20.1.8 plus a Rocky Linux 8 sysroot, for x86_64 hosts only. In its place, the same
# layout around LLVM's clang (bin), its libc++ (headers, static libraries) and the host's own glibc as sysroot. UBT then
# builds as it does on x64: libc++ linked statically, the same flags. Nothing is recreated when it is already right
# (UBT compares header times with the objects, and a fresh layout on every run means a full rebuild).
prepare_toolchain() {
  local f
  link() { [ "$(readlink "$2")" = "$1" ] || ln -sfn "$1" "$2"; }
  put() { [ -f "$1" ] && [ "$(cat "$1")" = "$2" ] || printf '%s\n' "$2" > "$1"; }
  mkdir -p "$tc/include/c++/v1" "$tc/include/sys" "$tc/lib64"
  put "$cache/linux-sdk/ToolchainVersion.txt" "v26_clang-$LLVM_VERSION-rockylinux8"
  link "$clang_dir/bin" "$tc/bin"; link /usr "$tc/usr"; link /usr/lib "$tc/lib"
  for f in "$clang_dir/include/c++/v1/"* "$clang_dir/include/aarch64-unknown-linux-gnu/c++/v1/__config_site"; do
    link "$f" "$tc/include/c++/v1/$(basename "$f")"
  done
  for f in libc++.a libc++abi.a; do link "$clang_dir/lib/aarch64-unknown-linux-gnu/$f" "$tc/lib64/$f"; done
  # glibc >= 2.30 has no <stropts.h> (UBA only needs ioctl); glibc >= 2.32 has no <sys/sysctl.h> (used on Mac only)
  put "$tc/include/stropts.h" "$(printf '%s\n' '/* shim: glibc >= 2.30 has no stropts.h; UE only needs ioctl */' '#pragma once' '#include <sys/ioctl.h>')"
  put "$tc/include/sys/sysctl.h" "$(printf '%s\n' '/* shim: glibc >= 2.32 has no sys/sysctl.h; UE calls sysctl() on Mac only */' '#pragma once')"
  # UE's triple (aarch64-unknown-linux-gnueabi) is not one clang maps to the distribution's GCC folder: a clang config file
  # for that triple names it (crtbeginS.o, libgcc)
  put "$clang_dir/bin/aarch64-unknown-linux-gnueabi.cfg" "--gcc-install-dir=$(ls -d /usr/lib/gcc/aarch64-linux-gnu/* | sort -V | tail -1)"
  export PATH="$clang_dir/bin:$PATH" LINUX_MULTIARCH_ROOT="$cache/linux-sdk"
  (cd "$src" && nice -n 15 Engine/Build/BatchFiles/BuildUBT.sh)
}

step_thirdparty() {
  prepare_toolchain
  CEF_ARM64_TARBALL="$downloads/$CEF_ARM64" "$here/scripts/third_party_arm64.sh" "$src" "$tc" "$cache/third-party" "$jobs"
}

# UBT 5.8 runs every action through UBA, and Epic ships libUbaHost.so for x64 Linux only, while UBA is itself built by
# UBT. UBT can still list UBA's compile commands (GenerateClangDatabase needs no executor): uba_bootstrap.py runs them.
step_uba() {
  prepare_toolchain
  local lib="$src/Engine/Binaries/LinuxArm64/UnrealBuildAccelerator/libUbaHost.so"
  local native="$src/Engine/Binaries/DotNET/UnrealBuildTool/runtimes/linux-arm64/native"
  if [ ! -f "$lib" ] || [ -n "$(find "$src/Engine/Source/Programs/UnrealBuildAccelerator" -newer "$lib" -name '*.cpp' -print -quit)" ]; then
    (cd "$src" && dotnet Engine/Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll -mode=GenerateClangDatabase -Target="UbaHost Linux Shipping" -NoUBA)
    (cd "$src" && python3 -B "$here/scripts/uba_bootstrap.py" "$src" "$tc" "$jobs")
    rm -f "$src/compile_commands.json"
  fi
  mkdir -p "$native"; cp -p "$lib" "$native/"
}

# The sample project: every default engine plugin plus MetaHuman, the MetaHuman Creator, Blackmagic capture and NDI (not
# on by default; built here to show they build and load on arm64), and the settings a new
# project from Epic's templates gets on Linux (SM6, Lumen, virtual shadow maps), plus hardware ray tracing (the GB10's
# Vulkan driver supports it) and what MetaHumans need (GPU skin cache for grooms).
write_project() {
  local dir; dir=$(dirname "$project")
  mkdir -p "$dir/Config" "$dir/Plugins"
  cp -Rp "$here/plugins/SparkTools" "$dir/Plugins/"   # -p: unchanged sources stay unchanged for UBT
  cat > "$dir/Config/DefaultEngine.ini" <<'INI'
[/Script/Engine.RendererSettings]
r.AllowStaticLighting=False
r.DynamicGlobalIlluminationMethod=1
r.ReflectionMethod=1
r.GenerateMeshDistanceFields=True
r.RayTracing=True
r.Lumen.HardwareRayTracing=True
r.Shadow.Virtual.Enable=1
r.SkinCache.CompileShaders=True
r.GPUSkin.Support16BitBoneIndex=True
r.GPUSkin.UnlimitedBoneInfluences=True

[/Script/LinuxTargetPlatform.LinuxTargetSettings]
-TargetedRHIs=SF_VULKAN_SM5
+TargetedRHIs=SF_VULKAN_SM6

[/Script/EngineSettings.GameMapsSettings]
GameDefaultMap=/Engine/Maps/Templates/OpenWorld.OpenWorld
EditorStartupMap=/Engine/Maps/Templates/OpenWorld.OpenWorld
INI
  # UE 5.8 cooks into a Zen store by default (BaseGame.ini), and Epic's Zen server has no arm64 Linux build: the cook
  # aborted in ZenStoreWriter. Cook to loose files, then pak, as before Zen.
  cat > "$dir/Config/DefaultGame.ini" <<'INI'
[/Script/UnrealEd.ProjectPackagingSettings]
bUseZenStore=False
INI
  # with no window manager the editor, once it loses keyboard focus, throttles itself to a few fps
  cat > "$dir/Config/DefaultEditorSettings.ini" <<'INI'
[/Script/UnrealEd.EditorPerformanceSettings]
bThrottleCPUWhenNotForeground=False
INI
  cat > "$project" <<'JSON'
{
	"FileVersion": 3,
	"EngineAssociation": "",
	"Category": "",
	"Description": "Unreal Engine 5.8 editor + MetaHuman on Linux ARM64 (DGX Spark / GB10)",
	"Plugins": [
		{ "Name": "MetaHuman", "Enabled": true },
		{ "Name": "MetaHumanCharacter", "Enabled": true },
		{ "Name": "SparkTools", "Enabled": true },
		{ "Name": "BlackmagicMedia", "Enabled": true },
		{ "Name": "NDIMedia", "Enabled": true },
		{ "Name": "ModelContextProtocol", "Enabled": true },
		{ "Name": "EditorToolset", "Enabled": true },
		{ "Name": "MetaHumanGenerator", "Enabled": true }
	]
}
JSON
  # Epic's experimental MCP server (ModelContextProtocol plugin) starts with the editor on http://localhost:8000/mcp.
  # The engine's HTTP server binds to the loopback address by default, so only this machine (or an SSH tunnel) reaches it.
  cat > "$dir/Config/DefaultEditorPerProjectUserSettings.ini" <<'INI'
[/Script/ModelContextProtocolEngine.ModelContextProtocolSettings]
bAutoStartServer=True
INI
}

ram_guard() {   # PROCESS_GROUP MIN_FREE_GIB
  local pg=$1 min=$2 stopped=0 avail
  while kill -0 -- "-$pg" 2>/dev/null; do
    avail=$(awk '/MemAvailable/ {print int($2 / 1048576)}' /proc/meminfo)
    if [ "$stopped" = 0 ] && [ "$avail" -lt "$min" ]; then
      kill -STOP -- "-$pg" 2>/dev/null; stopped=1; echo "$(date +%T) available memory $avail GiB: build paused"
    elif [ "$stopped" = 1 ] && [ "$avail" -ge $((min + 5)) ]; then
      kill -CONT -- "-$pg" 2>/dev/null; stopped=0; echo "$(date +%T) available memory $avail GiB: build resumed"
    fi
    sleep 5
  done
}

run_ubt() {
  local pg rc=0
  setsid nice -n 15 bash -c 'cd "$1" && shift && exec Engine/Build/BatchFiles/Linux/Build.sh "$@"' _ "$src" \
    -Target="$(basename "$project" .uproject)Editor Linux Development -Project=$project" \
    -Target="ShaderCompileWorker Linux Development" -Target="EpicWebHelper Linux Shipping" \
    -NoUBA -UBARootDir="$cache/uba" -MaxParallelActions="$jobs" &
  pg=$!
  ram_guard "$pg" "$min_free" &
  wait "$pg" || rc=$?
  return "$rc"
}

# The editor is the platform "Linux" built on an arm64 host, in Binaries/Linux; at run time the engine looks for its
# arm64 binaries in Binaries/LinuxArm64. Each plugin gets a LinuxArm64 link to its Linux folder; the engine's own
# LinuxArm64 folder gets links to the arm64 programs only (a second copy of the modules would make them ambiguous).
link_arm64_layout() {
  local d f
  find "$src/Engine/Plugins" "$(dirname "$project")/Plugins" -type d -path '*/Binaries/Linux' 2>/dev/null | while read -r d; do
    [ -e "$(dirname "$d")/LinuxArm64" ] || ln -s Linux "$(dirname "$d")/LinuxArm64"
  done
  mkdir -p "$src/Engine/Binaries/LinuxArm64"
  for f in "$src/Engine/Binaries/Linux/"*; do
    case "$(basename "$f")" in *.*) continue ;; esac
    [ -f "$f" ] && [ -x "$f" ] && file -b "$f" | grep -q aarch64 || continue
    [ -e "$src/Engine/Binaries/LinuxArm64/$(basename "$f")" ] || ln -s "../Linux/$(basename "$f")" "$src/Engine/Binaries/LinuxArm64/"
  done
}

step_build() {
  local rc before after
  prepare_toolchain
  write_project
  export UE_PYTHON_DIR="$cache/third-party/python3"   # the system Python, laid out by third_party_arm64.sh
  # FBX: Autodesk ships no arm64 Linux SDK. The editor links a generated stub (FBX import goes through ufbx instead);
  # its symbols come from the compiled objects, so the first build stops at the FBX links and runs once more.
  export UE_FBX_STUB_DIR="$cache/fbx-stub"
  [ -f "$UE_FBX_STUB_DIR/libfbxsdk.so" ] || python3 -B "$here/scripts/fbx_stub.py" "$src" "$tc" "$UE_FBX_STUB_DIR"
  rc=0; run_ubt || rc=$?
  if [ "$rc" != 0 ]; then
    before=$(wc -l < "$UE_FBX_STUB_DIR/symbols.txt")
    after=$(python3 -B "$here/scripts/fbx_stub.py" "$src" "$tc" "$UE_FBX_STUB_DIR")
    echo "FBX stub: $before -> $after symbols"
    if [ "$after" -gt "$before" ]; then rc=0; run_ubt || rc=$?; fi
  fi
  [ "$rc" = 0 ] || return "$rc"
  link_arm64_layout
  echo "editor ready: tools/editor.sh gui --engine $src --work $work --project $project"
}

for s in "${steps[@]}"; do
  t0=$(date +%s); echo "== $s ($(date +%T))"
  case "$s" in
    toolchain) step_toolchain ;;
    deps) step_deps ;;
    thirdparty) step_thirdparty ;;
    uba) step_uba ;;
    build) step_build ;;
    all) step_toolchain; step_deps; step_thirdparty; step_uba; step_build ;;
    *) echo "unknown step: $s" >&2; exit 2 ;;
  esac
  echo "== $s done in $(( $(date +%s) - t0 )) s"
done
