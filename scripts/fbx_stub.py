"""A stand-in libfbxsdk.so for the arm64 editor, 24 Nov (DGX Spark).

Autodesk ships the FBX SDK for x86_64 Linux only, and UnrealEd and a few plugins link it. This builds a shared library
exporting exactly the fbxsdk:: symbols the compiled objects use: every function returns 0 (a null FbxManager, false,
nothing imported), every data symbol (vtables, typeinfo, static members) is zero-filled. The editor starts and works;
FBX import and export do nothing. Called with no objects found, it writes an empty stub (the first build then fails at
the links that need FBX, and the next call has their objects to read).
Usage: python3 fbx_stub.py ENGINE_ROOT TOOLCHAIN_DIR OUT_DIR   -> OUT_DIR/libfbxsdk.so; prints the symbol count
"""
import subprocess
import sys
from pathlib import Path

root, tc, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
nm, filt = tc / 'bin' / 'llvm-nm', tc / 'bin' / 'llvm-cxxfilt'
out.mkdir(parents=True, exist_ok=True)

objects = [str(p) for base in (root / 'Engine' / 'Intermediate', root / 'Engine' / 'Plugins')
           for p in base.rglob('*.o') if '/Linux/arm64/' in str(p)]
wanted = set()
for i in range(0, len(objects), 400):
    r = subprocess.run([str(nm), '-u', '--no-sort', '--format=just-symbols', *objects[i:i + 400]], capture_output=True, text=True)
    wanted |= {s.strip() for s in r.stdout.split() if '6fbxsdk' in s}
wanted = sorted(wanted)
demangled = subprocess.run([str(filt)], input='\n'.join(wanted), capture_output=True, text=True).stdout.splitlines() if wanted else []

asm = ['\t.text']
data = ['\t.data', '\t.balign 16']
for sym, name in zip(wanted, demangled):
    if '(' in name and not name.startswith(('vtable for', 'typeinfo', 'VTT for', 'guard variable')):
        asm += [f'\t.globl {sym}', f'\t.type {sym},%function', f'{sym}:', '\tmov x0, #0', '\tret']
    else:
        data += [f'\t.globl {sym}', f'\t.type {sym},%object', f'\t.size {sym},1024', f'{sym}:', '\t.zero 1024']
(out / 'fbxsdk_stub.s').write_text('\n'.join(asm + data) + '\n')
(out / 'symbols.txt').write_text('\n'.join(wanted) + '\n')
subprocess.run([str(tc / 'bin' / 'clang'), '--target=aarch64-unknown-linux-gnueabi', f'--sysroot={tc}', '-shared', '-nostdlib',
                '-fuse-ld=lld', '-Wl,-soname,libfbxsdk.so', '-o', str(out / 'libfbxsdk.so'), str(out / 'fbxsdk_stub.s')], check=True)
print(len(wanted))
