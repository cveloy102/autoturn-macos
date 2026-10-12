#!/usr/bin/env python3
"""Verify locally signed metadata and the exact archive before publishing."""
import argparse, base64, hashlib, json, plistlib
from pathlib import Path
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
p=argparse.ArgumentParser()
p.add_argument('manifest',type=Path)
p.add_argument('assets',type=Path)
p.add_argument('--app',type=Path)
a=p.parse_args(); m=json.loads(a.manifest.read_text())
key=Ed25519PublicKey.from_public_bytes(base64.b64decode(Path('Resources/update-public-key.txt').read_text().strip(),validate=True))
envelope=json.loads(a.manifest.with_name('macos-update.json').read_text())
payload=base64.b64decode(envelope['payload'],validate=True)
key.verify(base64.b64decode(envelope['signature'],validate=True),payload)
metadata=json.loads(payload)
archive=a.assets/f"AutoTurn-{m['version']}-macOS.zip"
data=archive.read_bytes();digest=hashlib.sha256(data).hexdigest()
assert digest==m['sha256']==metadata['sha256'],'Archive checksum mismatch'
key.verify(base64.b64decode(metadata['signature'],validate=True),data)
assert metadata['version']==m['version'] and metadata['build']==m['build'],'Version mismatch'
assert metadata['archiveURL']==f"https://github.com/cveloy102/autoturn-macos/releases/download/macos-v{m['version']}/{archive.name}",'Archive URL mismatch'
candidate=json.loads((a.assets/'candidate.json').read_text())
assert candidate['commit']==m['commit'] and int(candidate['runID'])==m['runID'],'Candidate provenance mismatch'
for name,sha in candidate['sha256'].items():
    assert '/' not in name and hashlib.sha256((a.assets/name).read_bytes()).hexdigest()==sha,'Candidate file mismatch'
if a.app:
    info=plistlib.loads((a.app/'Contents/Info.plist').read_bytes())
    assert info['CFBundleShortVersionString']==m['version'] and int(info['CFBundleVersion'])==m['build']
    assert info['ATUpdatePublicKey']==Path('Resources/update-public-key.txt').read_text().strip()
    assert info['LSMinimumSystemVersion']==metadata['minimumOS']
print(f"Verified AutoTurn {m['version']} build {m['build']}: signatures, archive and candidate source")
