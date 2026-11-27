"""Builds UnrealBuildAccelerator's host library (libUbaHost.so) for linux-arm64 by hand, 24 Nov (DGX Spark).

UE 5.8's UnrealBuildTool runs every action through UBA, and Epic ships libUbaHost.so for x64 Linux only, while UBA itself
is built by UBT: a chicken and egg. UBT can still describe the compile actions (-mode=GenerateClangDatabase, which needs
no executor): this runs them (JOBS at a time, niced) and links the library with the arm64 builds of its third-party
libraries, into Engine/Binaries/LinuxArm64/UnrealBuildAccelerator/, where EpicGames.UBA/Library.props already looks.
Usage (from install.sh, toolchain and UBT ready): python3 uba_bootstrap.py ENGINE_ROOT TOOLCHAIN_DIR JOBS
"""
import concurrent.futures
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path

root, tc, jobs = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3])
db = json.loads((root / 'compile_commands.json').read_text())
src = root / 'Engine' / 'Source'
tp = src / 'ThirdParty'


def output_of(entry):
    """The .o a compile command writes (its -o, in the response file)."""
    cmd = entry.get('command') or ' '.join(entry['arguments'])
    rsp = re.search(r'@"?([^"\s]+\.rsp)"?', cmd)
    text = (Path(entry['directory']) / rsp[1]).read_text() if rsp else cmd
    out = re.search(r'-o\s+"?([^"\s]+)"?', text)
    return Path(entry['directory']) / out[1]


def compile_one(entry):
    obj = output_of(entry)
    if obj.is_file() and obj.stat().st_mtime > Path(entry['file']).stat().st_mtime:
        return obj, ''
    obj.parent.mkdir(parents=True, exist_ok=True)
    cmd = entry.get('command') or shlex.join(entry['arguments'])
    if entry['file'].endswith('.cpp'):   # the clang database leaves out the modules' PCH, which some headers rely on
        cmd += f" -include {shlex.quote(str(src / 'Programs/UnrealBuildAccelerator/Core/Public/UbaCorePch.h'))}"
    r = subprocess.run(['nice', '-n', '15', 'sh', '-c', cmd], cwd=entry['directory'], capture_output=True, text=True)
    if r.returncode:
        raise SystemExit(f"compilazione fallita: {entry['file']}\n{r.stdout[-3000:]}{r.stderr[-3000:]}")
    return obj, entry['file']


with concurrent.futures.ThreadPoolExecutor(jobs) as pool:
    objects = []
    for obj, done in pool.map(compile_one, db):
        objects.append(obj)
        if done:
            print('compiled', Path(done).name, flush=True)

out = root / 'Engine' / 'Binaries' / 'LinuxArm64' / 'UnrealBuildAccelerator' / 'libUbaHost.so'
out.parent.mkdir(parents=True, exist_ok=True)
libs = [tp / 'BLAKE3/1.3.1/lib/Unix/aarch64-unknown-linux-gnueabi/Release/libBLAKE3.a',
        src / 'Runtime/OodleDataCompression/Sdks/2.9.16/lib/LinuxArm64/liboo2corelinuxarm64.a',
        tp / 'OpenSSL/1.1.1t/lib/Unix/aarch64-unknown-linux-gnueabi/libssl.a',
        tp / 'OpenSSL/1.1.1t/lib/Unix/aarch64-unknown-linux-gnueabi/libcrypto.a']
missing = [str(p) for p in libs if not p.is_file()]
if missing:
    raise SystemExit('missing libraries: ' + ' '.join(missing))
link = [str(tc / 'bin' / 'clang++'), '-shared', '-fuse-ld=lld', '-target', 'aarch64-unknown-linux-gnueabi', f'--sysroot={tc}',
        '-nodefaultlibs', '-Wl,--no-undefined', '-Wl,-soname,libUbaHost.so', '-o', str(out), *map(str, objects),
        '-Wl,--start-group', *map(str, libs), '-Wl,--end-group',
        str(tc / 'lib64' / 'libc++.a'), str(tc / 'lib64' / 'libc++abi.a'),
        '-lm', '-lc', '-lpthread', '-ldl', '-lrt', '-lgcc_s', '-lgcc']
r = subprocess.run(link, capture_output=True, text=True)
if r.returncode:
    raise SystemExit('link fallito:\n' + r.stderr[-4000:])
print('libUbaHost.so ready:', out, os.path.getsize(out), 'bytes')
