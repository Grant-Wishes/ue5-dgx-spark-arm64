#!/usr/bin/env bash
# Exact versions of everything the arm64 editor build depends on, as a Markdown table. Usage: UE_ENGINE=... tools/versions.sh
set -uo pipefail
. "$(dirname "$0")/env.sh"
src=$UE_ENGINE
row() { printf '| %s | %s |\n' "$1" "$2"; }
echo "| Component | Version |"
echo "|---|---|"
row "Unreal Engine" "$(python3 -c "import json,sys; v=json.load(open(sys.argv[1])); print(f\"{v['MajorVersion']}.{v['MinorVersion']}.{v['PatchVersion']} (CL {v['CompatibleChangelist']}, branch {v['BranchName']})\")" "$src/Engine/Build/Build.version")"
row "Engine checkout" "$(git -C "$src" rev-parse --abbrev-ref HEAD 2>/dev/null) @ $(git -C "$src" rev-parse --short HEAD 2>/dev/null || echo '?')"
row "CPU" "$(uname -m), $(lscpu | awk -F: '/Model name/ {gsub(/^ +/,"",$2); m=$2} /Core\(s\) per socket/ {gsub(/ /,"",$2); printf "%s%s x %s", s, $2, m; s=" + "}')"
row "Memory" "$(free -g | awk '/Mem:/ {print $2" GiB (unified CPU/GPU)"}')"
row "GPU" "$(nvidia-smi --query-gpu=name --format=csv,noheader)"
row "NVIDIA driver" "$(nvidia-smi --query-gpu=driver_version --format=csv,noheader)"
row "CUDA (driver API)" "$(nvidia-smi | grep -oE 'CUDA Version: [0-9.]+' | awk '{print $3}')"
row "CUDA toolkit" "$(python3 -c "import json; print(json.load(open('/usr/local/cuda/version.json'))['cuda']['version'])" 2>/dev/null || echo 'not used')"
row "Vulkan (NVIDIA ICD API)" "$(python3 -c "import json; print(json.load(open('/usr/share/vulkan/icd.d/nvidia_icd.json'))['ICD']['api_version'])" 2>/dev/null)"
row "Vulkan loader" "$(dpkg-query -W -f='${Version}' libvulkan1 2>/dev/null)"
row "OS" "$(lsb_release -ds 2>/dev/null)"
row "Kernel" "$(uname -r)"
row "glibc" "$(ldd --version | head -1 | awk '{print $NF}')"
row "Xorg" "$(dpkg-query -W -f='${Version}' xserver-xorg-core 2>/dev/null)"
row "Clang (engine build)" "$("$UE_WORK/clang/bin/clang" --version | head -1)"
row ".NET SDK (UBT)" "$("$UE_WORK/dotnet/dotnet" --version)"
row "ISPC" "$("$src/Engine/Source/ThirdParty/Intel/ISPC/bin/LinuxArm64/ispc" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo 'not installed')"
row "Python (editor scripting)" "$(/usr/bin/python3 --version | awk '{print $2}')"
row "CMake (third-party libs)" "$(cmake --version | head -1 | awk '{print $3}')"
