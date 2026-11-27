#!/usr/bin/env bash
# Editor third-party static libraries that Epic ships for x86_64 Linux only, built for aarch64 from the sources in the
# engine tree (24 Nov, DGX Spark). Epic builds them with RunUAT BuildCMakeLib, which needs Perforce: plain CMake/make here,
# with the same compiler (clang 20) and, for C++, the same libc++ headers the engine uses. UBT's warnings listed them:
# GKlib and metis (C, mesh partitioning) and VHACD (C++, convex decomposition).
# Usage: third_party_arm64.sh ENGINE_ROOT TOOLCHAIN_DIR WORK_DIR [JOBS]
set -euo pipefail
src=$1 tc=$2 work=$3 jobs=${4:-3}
arch=aarch64-unknown-linux-gnueabi
tp="$src/Engine/Source/ThirdParty"
cflags="--target=$arch --sysroot=$tc -fPIC -O2 -DNDEBUG"
mkdir -p "$work"

cmake_lib() {   # NAME SOURCE_DIR LIB_NAME DEST_DIR [CMAKE ARGS...]
  local name=$1 dir=$2 lib=$3 dest=$4; shift 4
  [ -f "$dest/$lib" ] && return 0
  rm -rf "$work/$name"
  cmake -S "$dir" -B "$work/$name" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$tc/bin/clang" \
    -DCMAKE_C_FLAGS="$cflags" -DCMAKE_AR="$tc/bin/llvm-ar" -DCMAKE_RANLIB="$tc/bin/llvm-ranlib" "$@" > "$work/$name.cmake.log"
  nice -n 15 make -C "$work/$name" -j"$jobs" > "$work/$name.make.log"
  mkdir -p "$dest"
  cp "$(find "$work/$name" -name "$lib" | head -1)" "$dest/$lib"
  echo "$name: $dest/$lib"
}

cmake_lib GKlib "$tp/GKlib/8bd6bad" libGKlib.a "$tp/GKlib/8bd6bad/lib/Linux/$arch/Release"
cmake_lib metis "$tp/metis/5.2.1" libmetis.a "$tp/metis/5.2.1/lib/Linux/$arch/Release" -DGKLIB_PATH="$tp/GKlib/8bd6bad"

vhacd="$tp/VHACD/Lib/Linux/$arch"
if [ ! -f "$vhacd/libVHACD_fPIC.a" ]; then
  rm -rf "$work/VHACD"; cp -r "$tp/VHACD" "$work/VHACD"   # its Makefile writes objects beside the sources
  mkdir -p "$work/VHACD/Lib/Linux/$arch"
  nice -n 15 make -C "$work/VHACD/build/Linux" -j"$jobs" TARGET_ARCH="$arch" CXX="$tc/bin/clang++ --target=$arch --sysroot=$tc" \
    CPPFLAGS="-Wno-switch -Wno-unused-value -Wno-unused-variable -nostdinc++ -isystem $tc/include/c++/v1 -I../../inc/ -fvisibility=hidden -DNDEBUG -O2" \
    > "$work/VHACD.make.log"
  mkdir -p "$vhacd"; cp "$work/VHACD/Lib/Linux/$arch/"libVHACD*.a "$vhacd/"
  echo "VHACD: $vhacd"
fi

# SPIRV-Reflect (C, one file) and hlslcc (C++ with libc++, its own Makefile expects Epic's toolchain layout: ours has it).
# Both are the editor's Vulkan shader compiler path (ShaderFormatVulkan / ShaderCompilerCommon).
sr="$tp/SPIRV-Reflect/lib/Linux/$arch"
if [ ! -f "$sr/libSPIRV-Reflect.a" ]; then
  mkdir -p "$work/SPIRV-Reflect" "$sr"
  "$tc/bin/clang" $cflags -c "$tp/SPIRV-Reflect/SPIRV-Reflect/spirv_reflect.c" -o "$work/SPIRV-Reflect/spirv_reflect.o"
  "$tc/bin/llvm-ar" cr "$sr/libSPIRV-Reflect.a" "$work/SPIRV-Reflect/spirv_reflect.o"
  echo "SPIRV-Reflect: $sr"
fi
hl="$tp/hlslcc/hlslcc/lib/Linux/$arch"
if [ ! -f "$hl/libhlslcc.a" ]; then
  rm -rf "$work/hlslcc"; cp -r "$tp/hlslcc/hlslcc" "$work/hlslcc"
  mkdir -p "$work/hlslcc/lib/Linux/$arch"
  nice -n 15 make -C "$work/hlslcc/projects/Linux" -j"$jobs" lib LINUX_ROOT="$tc" TARGET_ARCH="$arch" > "$work/hlslcc.make.log" 2>&1
  mkdir -p "$hl"; cp "$work/hlslcc/lib/Linux/$arch/libhlslcc.a" "$hl/"
  echo "hlslcc: $hl"
fi

# Kiss FFT (C): its CMakeLists picks /usr/bin/clang itself and builds both libKissFFT.a and libKissFFT_fPIC.a.
kf="$tp/Kiss_FFT/kiss_fft129/Lib/Linux/Release/$arch"
if [ ! -f "$kf/libKissFFT_fPIC.a" ]; then
  rm -rf "$work/KissFFT"
  cmake -S "$tp/Kiss_FFT/kiss_fft129" -B "$work/KissFFT" -DCMAKE_BUILD_TYPE=Release > "$work/KissFFT.cmake.log"
  nice -n 15 make -C "$work/KissFFT" -j"$jobs" > "$work/KissFFT.make.log"
  # its CMakeLists hard-codes the output folder ../Lib/Linux/Release/x86_64-unknown-linux-gnu (relative to the build dir)
  mkdir -p "$kf"; cp "$work/Lib/Linux/Release/x86_64-unknown-linux-gnu/libKissFFT.a" "$work/Lib/Linux/Release/x86_64-unknown-linux-gnu/libKissFFT_fPIC.a" "$kf/"
  rm -rf "$work/Lib"
  echo "KissFFT: $kf"
fi

# etc2comp (C++, ETC2 texture encoder for the Android/iOS formats the editor loads): patch 0013 reads lib/Linux/<arch>.
etc="$tp/etc2comp/lib/Linux/$arch/Release"
if [ ! -f "$etc/libEtcLib.a" ]; then
  rm -rf "$work/etc2comp"
  cmake -S "$tp/etc2comp" -B "$work/etc2comp" -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_DEFAULT_CMP0056=NEW \
    -DCMAKE_C_COMPILER="$tc/bin/clang" -DCMAKE_CXX_COMPILER="$tc/bin/clang++" -DCMAKE_C_FLAGS="$cflags" \
    -DCMAKE_CXX_FLAGS="$cflags -std=c++11 -nostdinc++ -isystem $tc/include/c++/v1" \
    -DCMAKE_AR="$tc/bin/llvm-ar" -DCMAKE_RANLIB="$tc/bin/llvm-ranlib" > "$work/etc2comp.cmake.log" 2>&1
  nice -n 15 make -C "$work/etc2comp" -j"$jobs" EtcLib > "$work/etc2comp.make.log" 2>&1
  mkdir -p "$etc"; cp "$(find "$work/etc2comp" -name libEtcLib.a | head -1)" "$etc/"
  echo "etc2comp: $etc"
fi

# ShaderConductor (DirectXShaderCompiler + SPIRV-Cross): the editor's HLSL compiler for its Vulkan shaders, shipped as
# x86_64 .so only (patch 0012 reads the folder from the architecture). Epic's Build_ShaderConductor_Linux.sh cross-builds
# with Ninja (not on the Spark): a native make build here, same clang and libc++ linked statically like theirs.
scd="$src/Engine/Binaries/ThirdParty/ShaderConductor/Linux/$arch"
if [ ! -f "$scd/libShaderConductor.so" ]; then
  b="$work/ShaderConductor"; mkdir -p "$b"   # kept between attempts: DXC alone is ~1 h at 3 jobs
  ld="-fuse-ld=lld -nostdlib++ $tc/lib64/libc++.a $tc/lib64/libc++abi.a -lpthread"
  cmake -S "$tp/ShaderConductor/ShaderConductor" -B "$b" -G "Unix Makefiles" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER="$tc/bin/clang" -DCMAKE_CXX_COMPILER="$tc/bin/clang++" \
    -DCMAKE_C_FLAGS="--target=$arch --sysroot=$tc -fms-extensions" \
    -DCMAKE_CXX_FLAGS="--target=$arch --sysroot=$tc -std=c++17 -fms-extensions -Wno-invalid-specialization -nostdinc++ -isystem $tc/include/c++/v1" \
    -DCMAKE_EXE_LINKER_FLAGS="$ld" -DCMAKE_SHARED_LINKER_FLAGS="$ld" -DCMAKE_MODULE_LINKER_FLAGS="$ld" \
    -DCMAKE_AR="$tc/bin/llvm-ar" -DCMAKE_RANLIB="$tc/bin/llvm-ranlib" -DSC_ARCH_NAME=arm64 \
    -DPython3_EXECUTABLE=/usr/bin/python3 -DPYTHON_EXECUTABLE=/usr/bin/python3 -DSPIRV_CROSS_ENABLE_TESTS=OFF \
    -DSC_EXPLICIT_DLLSHUTDOWN=ON -DDXC_EXPLICIT_DLLSHUTDOWN=ON > "$b.cmake.log" 2>&1
  nice -n 15 make -C "$b" -j"$jobs" > "$b.make.log" 2>&1
  mkdir -p "$scd"
  for f in libdxcompiler.so libShaderConductor.so ShaderConductorCmd; do cp "$(find "$b" -name "$f" -type f | head -1)" "$scd/"; done
  echo "ShaderConductor: $scd"
fi

# FontConfig: the system library (aarch64, no -dev package for the unversioned .so), linked under the name patch 0013 reads.
fc="$tp/FontConfig/fontconfig-2.13.94/lib/Unix/$arch"
if [ ! -e "$fc/libfontconfig.so" ]; then
  mkdir -p "$fc"; ln -sfn /usr/lib/aarch64-linux-gnu/libfontconfig.so.1 "$fc/libfontconfig.so"
  echo "FontConfig: $fc"
fi

# ASTC texture encoder thunks (the editor's TextureFormatASTC aborts at start without the 5.0.1 one): Epic ships them for
# x86_64 Linux only; built here as their build_linux_thunks.bat does, from the in-tree astc-encoder sources with NEON in
# place of SSE4.1 and libc++ linked statically. Patch 0016 makes astcenc.Build.cs read the linuxarm64 names.
for v in 4.2.0 5.0.1; do
  so="$tp/astcenc/Thunks/libastcenc_thunk_linuxarm64_$v.so"
  [ -f "$so" ] && continue
  b="$work/astcenc-$v"; rm -rf "$b"
  case $v in 4.*) opts="-DISA_NEON=ON -DCLI=OFF" rdo= ;; *) opts="-DASTCENC_ISA_NEON=ON -DASTCENC_CLI=OFF" rdo=-DASTC_SUPPORTS_RDO ;; esac
  cxx="$cflags -O3 -std=c++17 -nostdinc++ -isystem $tc/include/c++/v1"   # astcenc sets its own floating-point flags
  cmake -S "$tp/astcenc/$v" -B "$b" -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$tc/bin/clang" \
    -DCMAKE_CXX_COMPILER="$tc/bin/clang++" -DCMAKE_CXX_FLAGS="$cxx" -DCMAKE_CXX_VISIBILITY_PRESET=hidden $opts \
    -DCMAKE_AR="$tc/bin/llvm-ar" -DCMAKE_RANLIB="$tc/bin/llvm-ranlib" > "$b.cmake.log" 2>&1
  # its own -Werror (after any flag passed in) meets warnings newer than 4.2.0 (clang 20): off in the generated build files
  find "$b" -name flags.make -exec sed -i 's/ -Werror\b//g' {} +
  nice -n 15 make -C "$b" -j"$jobs" astcenc-neon-static > "$b.make.log" 2>&1
  "$tc/bin/clang++" $cxx -ffp-contract=off $rdo -I"$tp/astcenc/$v/Source" -c "$tp/astcenc/astc_thunk.cpp" -o "$b/astc_thunk.o"
  "$tc/bin/clang++" --target=$arch --sysroot="$tc" -fuse-ld=lld -shared -nostdlib++ "$b/astc_thunk.o" \
    "$(find "$b" -name libastcenc-neon-static.a | head -1)" "$tc/lib64/libc++.a" "$tc/lib64/libc++abi.a" -lpthread -o "$so"
  echo "astcenc $v: $so"
done

# ISPC Texture Compressor (the BC6H/BC7/ASTC encoders TextureFormatIntelISPCTexComp loads at run time, patch 0019): Epic
# ships it for x86_64 Linux only. Built here from the in-tree sources (Epic's ASTC fix already in) with Intel's aarch64 ISPC
# and NEON, as its own Makefile.linux does on aarch64; libc++ linked statically like the engine's other .so thunks.
ispc="$src/Engine/Source/ThirdParty/Intel/ISPC/bin/LinuxArm64/ispc"
itc="$src/Engine/Binaries/ThirdParty/Intel/ISPCTexComp/LinuxArm64-Release"
if [ -x "$ispc" ] && [ ! -f "$itc/libispc_texcomp.so" ]; then
  b="$work/ISPCTexComp"; rm -rf "$b"; cp -r "$tp/Intel/ISPCTexComp/ISPCTextureCompressor-14d998c" "$b"
  for k in kernel kernel_astc; do
    "$ispc" -O2 --arch=aarch64 --target=neon-i32x4 --opt=fast-math --pic -o "$b/ispc_texcomp/${k}_ispc.o" \
      -h "$b/ispc_texcomp/${k}_ispc.h" "$b/ispc_texcomp/$k.ispc" > "$work/ISPCTexComp.$k.log" 2>&1
  done
  for c in ispc_texcomp ispc_texcomp_astc; do
    "$tc/bin/clang++" $cflags -std=c++11 -nostdinc++ -isystem "$tc/include/c++/v1" -I"$b" -c "$b/ispc_texcomp/$c.cpp" -o "$b/ispc_texcomp/$c.o"
  done
  mkdir -p "$itc"
  "$tc/bin/clang++" --target=$arch --sysroot="$tc" -fuse-ld=lld -shared -nostdlib++ "$b/ispc_texcomp/"*.o \
    "$tc/lib64/libc++.a" "$tc/lib64/libc++abi.a" -lpthread -o "$itc/libispc_texcomp.so"
  echo "ISPCTexComp: $itc"
fi

# CEF (Chromium Embedded Framework: the editor's web browser widget, patch 0020). Epic ships it for x86_64 Linux only.
# The public linuxarm64 build of the same CEF commit as UE 5.8's experimental 147.1.5 (g68529a5, published as 147.0.5;
# install.sh passes its archive in CEF_ARM64_TARBALL): headers and libcef_dll_wrapper.a (the C++ glue the engine links
# statically, built here with the engine's clang and libc++) where CEF3.build.cs reads them, the runtime laid out in
# Binaries/ThirdParty/CEF3/Linux/<version> as Epic's update_drop_linux.sh does (Resources minus locales beside libcef.so).
cefv="147.0.5+g68529a5+chromium-147.0.7727.49"
cefsrc="$tp/CEF3/cef_binary_${cefv}_linuxarm64"
cefrt="$src/Engine/Binaries/ThirdParty/CEF3/Linux/$cefv"
if [ -n "${CEF_ARM64_TARBALL:-}" ] && [ ! -f "$cefsrc/Release/libcef_dll_wrapper.a" ]; then
  b="$work/cef"; rm -rf "$b"; mkdir -p "$b"
  tar -xjf "$CEF_ARM64_TARBALL" -C "$b" --strip-components=1
  cmake -S "$b" -B "$b/build" -DCMAKE_BUILD_TYPE=Release -DPROJECT_ARCH=arm64 -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_C_COMPILER="$tc/bin/clang" -DCMAKE_CXX_COMPILER="$tc/bin/clang++" \
    -DCMAKE_C_FLAGS="--target=$arch --sysroot=$tc" \
    -DCMAKE_CXX_FLAGS="--target=$arch --sysroot=$tc -nostdinc++ -isystem $tc/include/c++/v1" \
    -DCMAKE_AR="$tc/bin/llvm-ar" -DCMAKE_RANLIB="$tc/bin/llvm-ranlib" > "$work/cef.cmake.log" 2>&1
  nice -n 15 make -C "$b/build" -j"$jobs" libcef_dll_wrapper > "$work/cef.make.log" 2>&1
  mkdir -p "$cefsrc/Release" "$cefrt/Resources"
  rm -rf "$cefsrc/include"; cp -a "$b/include" "$cefsrc/"
  cp "$(find "$b/build" -name libcef_dll_wrapper.a | head -1)" "$cefsrc/Release/"
  cp -a "$b/Release/." "$cefrt/"
  (cd "$b/Resources" && for f in *; do [ "$f" = locales ] || cp -a "$f" "$cefrt/"; done)
  rm -rf "$cefrt/Resources/locales"; cp -a "$b/Resources/locales" "$cefrt/Resources/"
  echo "CEF $cefv: $cefsrc, $cefrt"
fi

# SpeedTree v7 Core (the SpeedTree importer plugin, patch 0024): Epic ships the library for x86_64 Linux only, but its
# sources are in the tree. Built here as its Linux CMakeLists does (11 files), with the engine's clang and libc++.
st="$tp/SpeedTree/SpeedTreeSDK-v7.0"
stl="$st/Lib/Linux/$arch/Release"
if [ ! -f "$stl/libSpeedTreeCore_fPIC.a" ]; then
  b="$work/SpeedTree"; rm -rf "$b"; mkdir -p "$b" "$stl"
  for f in ScopeTrace Core ErrorHandler Evaluation/Key Fixed Parser Memory Wind AllocatorStats FileSystem CoordSys; do
    "$tc/bin/clang++" $cflags -std=c++11 -nostdinc++ -isystem "$tc/include/c++/v1" -Wno-everything \
      -I"$st/Source/Core/Source" -I"$st/Source/Core/Source/Evaluation" -I"$st/Include" \
      -c "$st/Source/Core/Source/$f.cpp" -o "$b/$(basename "$f").o"
  done
  "$tc/bin/llvm-ar" cr "$stl/libSpeedTreeCore_fPIC.a" "$b"/*.o
  cp "$stl/libSpeedTreeCore_fPIC.a" "$stl/libSpeedTreeCore.a"
  echo "SpeedTree: $stl"
fi

# NNEEditorOnnxTools (the NNE editor's ONNX external-data reader, patch 0027): Epic ships only prebuilt binaries, x86_64 on
# Linux. Our own implementation of its public C interface (nne_onnx_tools.cpp, no dependencies), libc++ linked statically.
nne="$src/Engine/Source/Editor/NNEEditor/Bin/LinuxArm64"
here_tp="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$nne/libNNEEditorOnnxTools.so" ] || [ "$here_tp/nne_onnx_tools.cpp" -nt "$nne/libNNEEditorOnnxTools.so" ]; then
  mkdir -p "$nne" "$work/nne"
  "$tc/bin/clang++" $cflags -std=c++17 -fvisibility=hidden -nostdinc++ -isystem "$tc/include/c++/v1" \
    -c "$here_tp/nne_onnx_tools.cpp" -o "$work/nne/nne_onnx_tools.o"
  "$tc/bin/clang++" --target=$arch --sysroot="$tc" -fuse-ld=lld -shared -nostdlib++ "$work/nne/nne_onnx_tools.o" \
    "$tc/lib64/libc++.a" "$tc/lib64/libc++abi.a" -lpthread -Wl,-soname,libNNEEditorOnnxTools.so -o "$nne/libNNEEditorOnnxTools.so"
  echo "NNEEditorOnnxTools: $nne"
fi

# Blackmagic DeckLink dispatcher (the BlackmagicMedia plugin's libBlackmagicLib.so, patch 0031): a small library that loads
# Blackmagic's own driver library (libDeckLinkAPI.so, from Desktop Video) at run time. Epic ships it for x86_64 Linux
# only; built here from the SDK's DeckLinkAPIDispatch.cpp in the plugin, as its CMakeLists does, libc++ linked statically.
bm="$src/Engine/Plugins/Media/BlackmagicMedia"
bml="$bm/Binaries/ThirdParty/LinuxArm64"
if [ -d "$bm" ] && [ ! -f "$bml/libBlackmagicLib.so" ]; then
  mkdir -p "$bml" "$work/blackmagic"
  "$tc/bin/clang++" $cflags -std=c++17 -nostdinc++ -isystem "$tc/include/c++/v1" -DUEBLACKMAGICDESIGN_EXPORTS \
    -I"$bm/Source/ThirdParty/BlackmagicLib/Include" -I"$bm/Source/ThirdParty/BlackmagicLib/Include/Linux" \
    -c "$bm/Source/ThirdParty/BlackmagicLib/Include/Linux/DeckLinkAPIDispatch.cpp" -o "$work/blackmagic/DeckLinkAPIDispatch.o"
  "$tc/bin/clang++" --target=$arch --sysroot="$tc" -fuse-ld=lld -shared -nostdlib++ "$work/blackmagic/DeckLinkAPIDispatch.o" \
    "$tc/lib64/libc++.a" "$tc/lib64/libc++abi.a" -lpthread -ldl -Wl,-soname,libBlackmagicLib.so -o "$bml/libBlackmagicLib.so"
  echo "BlackmagicLib: $bml"
fi

# NDI runtime (the NDIMedia plugin, patch 0032): Epic bundles libndi for x86_64 Linux only, and it is not ours to
# redistribute. With NDI_SDK_DIR set to the unpacked "NDI SDK for Linux" (from ndi.video, its licence accepted by you),
# the SDK's aarch64 libndi goes where the plugin loads it.
ndi="$src/Engine/Plugins/Media/NDIMedia/Binaries/ThirdParty/LinuxArm64"
if [ -n "${NDI_SDK_DIR:-}" ] && [ ! -f "$ndi/libndi.so.6" ]; then
  nl=$(ls "$NDI_SDK_DIR"/lib/aarch64-rpi4-linux-gnueabi/libndi.so.6.*.* 2>/dev/null | head -1)
  [ -n "$nl" ] || { echo "NDI_SDK_DIR: no lib/aarch64-rpi4-linux-gnueabi/libndi.so.6.x.y in $NDI_SDK_DIR" >&2; exit 1; }
  mkdir -p "$ndi"; cp "$nl" "$ndi/libndi.so.6"
  cp "$NDI_SDK_DIR/licenses/libndi_licenses.txt" "$ndi/" 2>/dev/null || true
  echo "NDI runtime: $ndi ($(basename "$nl"))"
fi

# libsndfile (the editor's audio import, loaded at run time; patch 0023): the system library is the same 1.2.2 Epic ships
# for x86_64 Linux (libsndfile1 1.2.2 on Ubuntu 24.04)
sf="$src/Engine/Binaries/ThirdParty/libsndfile/LinuxArm64"
if [ ! -e "$sf/libsndfile.so.1" ]; then
  mkdir -p "$sf"; ln -sfn /usr/lib/aarch64-linux-gnu/libsndfile.so.1 "$sf/libsndfile.so.1"
  echo "libsndfile: $sf"
fi

# Python for the editor's Python scripting (patch 0015): Epic's Linux SDK is x86_64 only, so a root laid out like theirs
# over the system Python 3 (headers from python3-dev, the shared library, the standard library). install.sh points
# UE_PYTHON_DIR here; the editor uses it as Python home.
py="$work/python3"; pv=$(/usr/bin/python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
if [ ! -e "$py/lib/libpython$pv.so.1.0" ]; then
  mkdir -p "$py/lib"
  ln -sfn "/usr/include/python$pv" "$py/include"
  ln -sfn "/usr/lib/aarch64-linux-gnu/libpython$pv.so.1.0" "$py/lib/libpython$pv.so"
  # the .so.1.0 name is the one PythonScriptPluginPreload opens with global symbols, which the standard library's
  # extension modules (_ssl...) need
  ln -sfn "/usr/lib/aarch64-linux-gnu/libpython$pv.so.1.0" "$py/lib/libpython$pv.so.1.0"
  ln -sfn "/usr/lib/python$pv" "$py/lib/python$pv"
  echo "Python $pv: $py"
fi

# Oodle (data, network, texture) and OpenXR ship their arm64 Linux builds in folders named LinuxArm64, while their
# Build.cs read the folder from Target.Platform ("Linux" here): the arm64 files (other names, no clash) are linked
# beside the x86_64 ones.
cd "$src/Engine"
find Source/Runtime/OodleDataCompression/Sdks Source/Developer/TextureFormatOodle/Sdks Plugins/Compression/OodleNetwork/Sdks \
     Binaries/ThirdParty/OpenXR -type d -name LinuxArm64 | while read -r d; do
  mkdir -p "$(dirname "$d")/Linux"
  for f in "$d"/*; do
    [ -e "$(dirname "$d")/Linux/$(basename "$f")" ] || ln -s "../LinuxArm64/$(basename "$f")" "$(dirname "$d")/Linux/$(basename "$f")"
  done
done
echo "arm64 libraries linked beside the Linux ones"
