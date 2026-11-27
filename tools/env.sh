# Sourced by the tools: the same layout build.sh uses. Set UE_ENGINE (the engine checkout), optionally UE_WORK
# (default <engine>/../ue-arm64-work) and UE_PROJECT (default <work>/SparkMH/SparkMH.uproject).
: "${UE_ENGINE:?set UE_ENGINE to the engine checkout}"
UE_ENGINE=$(cd "$UE_ENGINE" && pwd)
UE_WORK=${UE_WORK:-$(cd "$UE_ENGINE/.." && pwd)/ue-arm64-work}
UE_PROJECT=${UE_PROJECT:-$UE_WORK/SparkMH/SparkMH.uproject}
UE_LOGS=${UE_LOGS:-$UE_WORK/logs}
mkdir -p "$UE_LOGS"
_c="$UE_WORK/cache"
export HOME="$_c/home" XDG_CONFIG_HOME="$_c/xdg-config" XDG_DATA_HOME="$_c/xdg-data" XDG_CACHE_HOME="$_c/xdg-cache"
export DOTNET_ROOT="$UE_WORK/dotnet" PATH="$UE_WORK/dotnet:$PATH" UE_USE_SYSTEM_DOTNET=1
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 DOTNET_CLI_HOME="$_c/dotnet-home" NUGET_PACKAGES="$_c/nuget"
export UE_ENGINE UE_WORK UE_PROJECT UE_LOGS
