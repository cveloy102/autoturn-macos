#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
APP="$ROOT/dist/AutoTurn.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
OUT="$ROOT/dist/candidate"
mkdir -p "$OUT"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/AutoTurn-$VERSION-macOS.zip"
git archive --format=tar.gz --prefix="AutoTurn-$VERSION-source/" HEAD > "$OUT/AutoTurn-$VERSION-source.tar.gz"
# Full corresponding patched sources, including licenses and exact build inputs.
COPY="$ROOT/.build/corresponding-source"
rm -rf "$COPY"
mkdir -p "$COPY/routing-core" "$COPY/amneziawg-go"
rsync -a --exclude=.git "$ROOT/third_party/routing-core/source/" "$COPY/routing-core/"
rsync -a --exclude=.git "$ROOT/.build/amneziawg-go/" "$COPY/amneziawg-go/"
cp "$ROOT/scripts/prepare-routing-core.sh" "$ROOT/scripts/build.sh" "$COPY/"
cp "$ROOT/DEVELOPMENT.md" "$COPY/BUILD.md"
tar -czf "$OUT/AutoTurn-$VERSION-third-party-source.tar.gz" -C "$ROOT/.build" corresponding-source
python3 - "$OUT" <<'PY'
import hashlib,json,os,subprocess,sys
from pathlib import Path
out=Path(sys.argv[1])
manifest={'commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'runID':os.environ.get('GITHUB_RUN_ID'),'sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in out.glob('*') if p.is_file()}}
(out/'candidate.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
