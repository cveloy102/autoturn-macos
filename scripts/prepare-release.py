#!/usr/bin/env python3
"""Sign macOS GitHub release assets. Private key never belongs in the repository."""
import argparse, base64, hashlib, json, os, plistlib, subprocess
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, PublicFormat, NoEncryption, load_pem_private_key

parser = argparse.ArgumentParser()
parser.add_argument('--key', type=Path, required=True)
parser.add_argument('--init', action='store_true')
parser.add_argument('--notes', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
if args.init:
    if args.key.exists(): raise SystemExit('Key already exists; it was not changed.')
    args.key.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    key = Ed25519PrivateKey.generate()
    fd = os.open(args.key, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as out: out.write(key.private_bytes(Encoding.PEM, PrivateFormat.PKCS8, NoEncryption()))
    public = base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()
    (root / 'Resources/update-public-key.txt').write_text(public + '\n')
    print('Signing key created; public key saved. Keep a separate backup of the private key.')
    raise SystemExit(0)
key = load_pem_private_key(args.key.read_bytes(), password=None)
if not isinstance(key, Ed25519PrivateKey): raise SystemExit('Expected an Ed25519 private key.')
app = root / 'dist/AutoTurn.app'
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
public = base64.b64encode(key.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()
if info.get('ATUpdatePublicKey') != public: raise SystemExit('App update public key differs from signing key; rebuild first.')
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
for component in ('Contents/MacOS/AutoTurn', 'Contents/Library/LaunchServices/AutoTurnHelper', 'Contents/Resources/amneziawg-go'):
    subprocess.run(['/usr/bin/lipo', str(app / component), '-verify_arch', 'x86_64', 'arm64'], check=True)
version, build = info['CFBundleShortVersionString'], int(info['CFBundleVersion'])
archive = root / f'dist/AutoTurn-{version}-macOS.zip'
subprocess.run(['/usr/bin/ditto','-c','-k','--sequesterRsrc','--keepParent',str(app),str(archive)],check=True)
data = archive.read_bytes()
payload = json.dumps({'version':version,'build':build,'minimumOS':info['LSMinimumSystemVersion'],
    'archiveURL':f'https://github.com/cveloy102/autoturn-macos/releases/download/macos-v{version}/{archive.name}',
    'sha256':hashlib.sha256(data).hexdigest(),'signature':base64.b64encode(key.sign(data)).decode(),
    'notes':args.notes.read_text() if args.notes else f'AutoTurn {version}'},ensure_ascii=False,separators=(',',':')).encode()
envelope = {'payload':base64.b64encode(payload).decode(),'signature':base64.b64encode(key.sign(payload)).decode()}
(root/'dist/macos-update.json').write_text(json.dumps(envelope,separators=(',',':')))
print('Signed archive and macos-update.json ready. Nothing uploaded.')
