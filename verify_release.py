"""Checks a built release zip before it ships. Exits 1 and lists every problem it finds.

    python verify_release.py dist/HoursWellSpent-<version>.zip <layer id> <version> [forbidden word ...]

Reads the zip's raw central directory, not zipfile's view of it: on Windows zipfile turns
backslashes into slashes when it reads, so it would hide the one defect it most needs to catch.
"""
import json
import struct
import sys
import zipfile

zip_path, layer_id, version = sys.argv[1:4]
forbidden = [w.lower().encode() for w in sys.argv[4:] if w]
problems = []

raw = open(zip_path, 'rb').read()
raw_names = []
pos = 0
while True:
    pos = raw.find(b'PK\x01\x02', pos)
    if pos < 0:
        break
    name_len = struct.unpack('<H', raw[pos + 28:pos + 30])[0]
    raw_names.append(raw[pos + 46:pos + 46 + name_len])
    pos += 46

# The zip spec requires '/' separators. Tools that follow it unpack a '\' name as one flat file.
for n in raw_names:
    if b'\\' in n:
        problems.append(f'backslash in entry name: {n!r}')

z = zipfile.ZipFile(zip_path)
names = [n for n in z.namelist() if not n.endswith('/')]
if len(z.namelist()) != len(raw_names):
    problems.append(f'zipfile sees {len(z.namelist())} entries, the central directory has {len(raw_names)}')

external = 'SKSE/Plugins/SkyrimNet/external/'
layer = external + layer_id + '/'
expected = [
    'HoursWellSpent.esp',
    'Scripts/HWS_Main.pex',
    'Scripts/HWS_PlayerAlias.pex',
    layer + 'manifest.json',
    layer + 'actions/SpendTimeTogether.yaml',
    layer + 'prompts/hws_scene.prompt',
]
for e in expected:
    if e not in names:
        problems.append(f'missing: {e}')

# SkyrimNet rejects any folder under external/ that has no manifest.json, and a store folder must be
# named for its manifest id. So: exactly one layer folder, ours, with a manifest whose id matches.
layer_dirs = sorted({n[len(external):].split('/')[0] for n in names if n.startswith(external)})
if layer_dirs != [layer_id]:
    problems.append(f'layer folders under external/: {layer_dirs}, expected only [{layer_id!r}]')
for d in layer_dirs:
    if external + d + '/manifest.json' not in names:
        problems.append(f'layer folder without manifest.json: {d}')
if layer + 'manifest.json' in names:
    try:
        manifest = json.loads(z.read(layer + 'manifest.json').decode('utf-8'))
        if manifest.get('id') != layer_id:
            problems.append(f"manifest id {manifest.get('id')!r} != folder name {layer_id!r}")
        if manifest.get('version') != version:
            problems.append(f"manifest version {manifest.get('version')!r} != release version {version!r}")
    except ValueError as err:
        problems.append(f'manifest.json is not valid JSON: {err}')

# Mod-manager bookkeeping that slipped into the stage would ship as junk SkyrimNet warns about.
for n in names:
    if '__folder_managed_by_vortex' in n or n.lower().endswith(('.tmp', '.bak')):
        problems.append(f'junk file: {n}')

for n in names:
    data = z.read(n).lower()
    for w in forbidden:
        if w in data or w in n.lower().encode():
            problems.append(f'{n} contains {w.decode()!r}')

if problems:
    print(f'release check FAILED for {zip_path}:')
    for p in problems:
        print('  - ' + p)
    sys.exit(1)
print(f'release check: {len(names)} files, layer {layer_id} {version}, 0 problems')
