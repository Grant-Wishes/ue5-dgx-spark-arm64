"""Fetches the engine's own tool files that the platform exclusions of GitDependencies dropped, 24 Nov (DGX Spark).

GitDependencies' --exclude=<X> drops every file in a folder named X: that keeps Windows/Mac/Android/iOS binaries off the
Spark, but also drops build-tool sources and resources under Engine/Source/Programs and Engine/Build (AutomationTool's
IOS project failed on its missing Resources/GreenCheck.png). This fetches exactly those files from Epic's CDN, the way
GitDependencies does (gzip packs, blobs at offsets, SHA-1 checked), and leaves everything else alone.
Usage: python3 gitdeps_tools.py ENGINE_ROOT EXCLUDED_NAME...
"""
import gzip
import hashlib
import os
import sys
import urllib.request
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

root, excluded = Path(sys.argv[1]), set(sys.argv[2:])
PREFIXES = ('Engine/Source/Programs/', 'Engine/Build/')
manifest = ET.parse(root / 'Engine/Build/Commit.gitdeps.xml').getroot()
base = manifest.get('BaseUrl')
blobs = {b.get('Hash'): b for b in manifest.iter('Blob')}
packs = {p.get('Hash'): p for p in manifest.iter('Pack')}

wanted = defaultdict(list)   # pack -> [(file, blob, executable)]
for f in manifest.iter('File'):
    name = f.get('Name')
    if name.startswith(PREFIXES) and set(name.split('/')[:-1]) & excluded and not (root / name).is_file():
        blob = blobs[f.get('Hash')]
        wanted[blob.get('PackHash')].append((name, blob, f.get('IsExecutable') == 'true'))

total = 0
for pack_hash, files in wanted.items():
    pack = packs[pack_hash]
    url = f"{base}/{pack.get('RemotePath')}/{pack_hash}"
    with urllib.request.urlopen(url, timeout=120) as r:
        data = gzip.decompress(r.read())
    for name, blob, executable in files:
        off, size = int(blob.get('PackOffset')), int(blob.get('Size'))
        content = data[off:off + size]
        if hashlib.sha1(content).hexdigest() != blob.get('Hash'):
            sys.exit(f'hash sbagliato per {name}')
        dst = root / name
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(content)
        if executable:
            os.chmod(dst, 0o775)
        total += 1
print(f'tool files fetched back: {total} from {len(wanted)} packs')
