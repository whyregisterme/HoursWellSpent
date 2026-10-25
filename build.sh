#!/bin/bash
# Builds Hours Well Spent into dist/HoursWellSpent-<version>.zip, a mod you install with Vortex.
#
#   bash build.sh
#
# Nothing here writes into the game's Data/ folder or SkyrimNet's live state: everything is built
# in build/ and zipped into dist/. It only READS the game install: the script sources and Papyrus
# flags file it compiles against.
#
# Steps: compile Papyrus (Caprica) -> build the .esp from its Spriggit source -> round-trip the .esp
# back to JSON and diff it against the source, because Spriggit drops unknown fields silently ->
# stage the Data layout -> zip.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$(cd "$HERE/../.." && pwd)"
VERSION="$(python -c "import json;print(json.load(open(r'$(cygpath -w "$HERE/layer/whyregister.hours-well-spent/manifest.json")'))['version'])")"
NAME="HoursWellSpent"
LAYER_ID="whyregister.hours-well-spent"

BUILD="$HERE/build"
STAGE="$BUILD/stage"
rm -rf "$BUILD"
mkdir -p "$STAGE/Scripts" "$STAGE/Source/Scripts" "$STAGE/SKSE/Plugins/SkyrimNet/external" "$HERE/dist"

echo "== 1/6 compile Papyrus"
# Bethesda's flags file (Hidden, Conditional), read from the game's script sources.
FLAGS="$(cygpath -w "$TOOLS/../Data/Source/Scripts/TESV_Papyrus_Flags.flg")"
# Compile against the game's own script sources, not the example repo's headers: those have the
# events stripped (no OnUpdate/OnHit), and the game's copies match the SkyrimNet, SKSE, PapyrusUtil
# and Papyrus Extender versions actually installed. Data/Scripts/Source comes first: that is where
# SKSE put its extended Form/ObjectReference/Actor (GetDisplayName etc.); Data/Source/Scripts has
# the vanilla ones, plus files SKSE does not touch (Debug).
IMPORTS="$(cygpath -w "$HERE/scripts");$(cygpath -w "$TOOLS/../Data/Scripts/Source");$(cygpath -w "$TOOLS/../Data/Source/Scripts")"
for psc in "$HERE"/scripts/*.psc; do
    "$TOOLS/Caprica/Caprica.exe" --game skyrim --ignorecwd -q --import "$IMPORTS" --flags "$FLAGS" \
        --output "$(cygpath -w "$STAGE/Scripts")" "$(cygpath -w "$psc")"
done
# Every .pex header records the source path, Windows user and machine name of whoever compiled it.
# Replace them with the bare file name and the author's handle, as Bethesda's own scripts carry.
# The three are length-prefixed strings right after the fixed 16-byte header and nothing points into them.
python - "$(cygpath -w "$STAGE/Scripts")" <<'EOF'
import os, struct, sys
for name in os.listdir(sys.argv[1]):
    path = os.path.join(sys.argv[1], name)
    data = open(path, 'rb').read()
    assert data[:4] == b'\xFA\x57\xC0\xDE', name
    pos = 16
    for _ in range(3):
        pos += 2 + struct.unpack('>H', data[pos:pos + 2])[0]
    new = b''.join(struct.pack('>H', len(s)) + s
                   for s in (name[:-4].encode() + b'.psc', b'whyregister', b''))
    open(path, 'wb').write(data[:16] + new + data[pos:])
EOF
if grep -aqi "$USERNAME" "$STAGE"/Scripts/*.pex; then echo "pex still names $USERNAME"; exit 1; fi
ls "$STAGE/Scripts"

echo "== 2/6 build $NAME.esp"
bash "$TOOLS/spriggit-cli.sh" deserialize --InputPath "$HERE/spriggit/$NAME" --OutputPath "$STAGE/$NAME.esp" 2>&1 | tail -1

echo "== 3/6 round-trip check"
bash "$TOOLS/spriggit-cli.sh" serialize --InputPath "$STAGE/$NAME.esp" --OutputPath "$BUILD/roundtrip/$NAME" \
    --GameRelease SkyrimSE --PackageName Spriggit.Json --PackageVersion 0.41.0 2>&1 | tail -1
python - "$(cygpath -w "$HERE/spriggit/$NAME")" "$(cygpath -w "$BUILD/roundtrip/$NAME")" <<'EOF'
import json, os, sys
src, back = sys.argv[1], sys.argv[2]
def load(root):
    out = {}
    for d, _, files in os.walk(root):
        for f in files:
            if f.endswith('.json'):
                p = os.path.join(d, f)
                out[os.path.relpath(p, root)] = json.load(open(p, encoding='utf-8-sig'))
    return out
a, b = load(src), load(back)
bad = 0
for k in sorted(set(a) | set(b)):
    if k not in b:
        print('MISSING after round trip:', k); bad += 1
    elif k not in a:
        print('EXTRA after round trip:', k); bad += 1
    elif a[k] != b[k]:
        print('CHANGED after round trip:', k)
        for key in sorted(set(a[k]) | set(b[k])):
            if a[k].get(key) != b[k].get(key):
                print('   ', key, ':', json.dumps(a[k].get(key))[:200], '->', json.dumps(b[k].get(key))[:200])
        bad += 1
print('round trip: %d file(s), %d difference(s)' % (len(a), bad))
sys.exit(1 if bad else 0)
EOF

echo "== 4/6 stage"
cp "$HERE"/scripts/*.psc "$STAGE/Source/Scripts/"
cp -r "$HERE/layer/$LAYER_ID" "$STAGE/SKSE/Plugins/SkyrimNet/external/"
# Named after the mod so it never collides with another mod's LICENSE in Data/.
cp "$HERE/LICENSE" "$STAGE/$NAME-LICENSE.txt"
(cd "$STAGE" && find . -type f | sort)

echo "== 5/6 zip"
ZIP="$HERE/dist/$NAME-$VERSION.zip"
rm -f "$ZIP"
# Not Compress-Archive: Windows PowerShell 5.1 writes '\' into entry names, against the zip spec, and
# extractors that follow the spec unpack those as flat files with backslashes in their names.
python - "$(cygpath -w "$STAGE")" "$(cygpath -w "$ZIP")" <<'EOF'
import os, sys, zipfile
stage, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(stage):
        dirs.sort()
        for f in sorted(files):
            full = os.path.join(root, f)
            z.write(full, os.path.relpath(full, stage).replace(os.sep, '/'))
EOF
ls -la "$ZIP"

echo "== 6/6 release check"
# Forbidden in any shipped file: identifying strings.
python "$(cygpath -w "$HERE/verify_release.py")" "$(cygpath -w "$ZIP")" "$LAYER_ID" "$VERSION" "$USERNAME" "$COMPUTERNAME" "SteamLibrary"
