#!/bin/bash
# What the demo video's terminal shows, each command as it runs: the CPU architecture, the GPU, the engine version, the
# editor binary's architecture, then the GPU load live (nvidia-smi every second, on one line).
UE=${UE_ENGINE:?set UE_ENGINE to the engine checkout}
p() { printf '\033[1;32m$\033[0m %s\n' "$1"; eval "$1"; }
clear
p "cd $UE"
p "uname -m"
p "nvidia-smi --query-gpu=name,driver_version --format=csv,noheader"
p "grep -E 'Major|Minor|Patch' Engine/Build/Build.version | tr -d '\n\t '; echo"
p "file -bL Engine/Binaries/Linux/UnrealEditor | cut -d, -f1-2"
p "nvidia-smi --query-gpu=utilization.gpu,power.draw --format=csv,noheader -l 1 | stdbuf -o0 tr '\n' '\r'"
