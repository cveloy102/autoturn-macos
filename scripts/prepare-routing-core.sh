#!/bin/bash
set -euo pipefail
export GOTOOLCHAIN=${GOTOOLCHAIN:-go1.26.9}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST="$ROOT/third_party/routing-core"
GO=${AT_GO:-go}
mkdir -p "$DEST"
SOURCE="$DEST/source"
if [ ! -d "$SOURCE/.git" ]; then git clone --depth 1 --branch v1.14.3 https://github.com/SagerNet/sing-box.git "$SOURCE"; fi
[ "$(git -C "$SOURCE" rev-parse HEAD)" = '7054cac5124465ffdb145870d7c01885566711b1' ] || { echo 'Unexpected routing core commit'; exit 1; }
if git -C "$SOURCE" apply --check "$ROOT/third_party/routing-core-patches/autoturn.patch" 2>/dev/null; then
 git -C "$SOURCE" apply "$ROOT/third_party/routing-core-patches/autoturn.patch"
else
 git -C "$SOURCE" apply --reverse --check "$ROOT/third_party/routing-core-patches/autoturn.patch"
fi
cp "$ROOT/third_party/routing-core-patches/autoturn.go" "$ROOT/third_party/routing-core-patches/autoturn_test.go" "$SOURCE/common/sniff/"
cp "$ROOT/third_party/routing-core-patches/autoturn_dns_test.go" "$SOURCE/dns/"
CGO_ENABLED=0 "$GO" test -C "$SOURCE" -tags with_gvisor,with_quic ./common/sniff
CGO_ENABLED=0 "$GO" test -C "$SOURCE" -tags with_gvisor,with_quic ./dns -run TestAutoTurnDNSLeaseCeiling
for ARCH in amd64 arm64; do
 CGO_ENABLED=0 GOOS=darwin GOARCH="$ARCH" "$GO" build -C "$SOURCE" -tags with_gvisor,with_quic -trimpath -ldflags '-s -w -X github.com/sagernet/sing-box/constant.Version=1.14.3-autoturn1' -o "$DEST/sing-box-$ARCH" ./cmd/sing-box
done
/usr/bin/lipo -create "$DEST/sing-box-amd64" "$DEST/sing-box-arm64" -output "$DEST/sing-box"
cp "$SOURCE/LICENSE" "$DEST/LICENSE"
chmod +x "$DEST/sing-box"
"$DEST/sing-box" version
