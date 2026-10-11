#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$ROOT/.build"
DIST="$ROOT/dist"
mkdir -p "$BUILD" "$DIST"
if [ -n "${DEVELOPER_DIR:-}" ]; then
 SWIFTC=$(xcrun --find swiftc)
 SDK=$(xcrun --sdk macosx --show-sdk-path)
elif [ -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
 SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc
 SDK=$(find /Library/Developer/CommandLineTools/SDKs -maxdepth 1 -name 'MacOSX.sdk' -print -quit)
else
 SWIFTC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
 SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
fi
LIPO=$(xcrun --find lipo)
ARCHS=${AT_ARCHS:-'x86_64 arm64'}
ENGINE_SOURCE=${AT_ENGINE_SOURCE:-"$BUILD/amneziawg-go"}
GIT=${AT_GIT:-git}
if [ ! -d "$ENGINE_SOURCE/.git" ]; then "$GIT" clone --depth 1 --branch v3.1.20260828 https://github.com/amnezia-vpn/amneziawg-go.git "$ENGINE_SOURCE"; fi
[ "$("$GIT" -C "$ENGINE_SOURCE" rev-parse HEAD)" = 'b5928efb6ca19f0153958460c3d141f04abc5c2e' ] || { echo 'Unexpected engine commit'; exit 1; }
# Upstream's Makefile generates this constant; linker -X cannot replace a const.
printf 'package main\n\nconst Version = "v3.1.20260828"\n' > "$ENGINE_SOURCE/version.go"
APP="$DIST/AutoTurn.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchServices"
for ARCH in $ARCHS; do
 TARGET="$ARCH-apple-macosx${AT_DEPLOYMENT_TARGET:-13.0}"
 "$SWIFTC" -swift-version 5 -O -whole-module-optimization -sdk "$SDK" -target "$TARGET" -module-name AutoTurn "$ROOT"/Sources/Shared/*.swift "$ROOT"/Sources/App/*.swift -o "$BUILD/AutoTurn-$ARCH" -framework AppKit -framework Security -framework CryptoKit -framework UserNotifications -framework CoreWLAN -framework CoreLocation -framework Network -framework SystemConfiguration
 if [ "${AT_UI_ONLY:-0}" != 1 ]; then
 "$SWIFTC" -swift-version 5 -O -whole-module-optimization -sdk "$SDK" -target "$TARGET" -module-name AutoTurnHelper "$ROOT"/Sources/Shared/*.swift "$ROOT"/Sources/Helper/*.swift -o "$BUILD/AutoTurnHelper-$ARCH" -framework Foundation -framework Security -framework Network -framework SystemConfiguration
 GOARCH=amd64; [ "$ARCH" != arm64 ] || GOARCH=arm64
 (cd "$ENGINE_SOURCE" && CGO_ENABLED=0 GOOS=darwin GOARCH="$GOARCH" go build -buildvcs=false -trimpath -ldflags '-X github.com/amnezia-vpn/amneziawg-go/v3/ipc.socketDirectory=/var/run/autoturn/uapi' -o "$BUILD/engine-$ARCH" .)
 else
  for COMPONENT in "$BUILD/AutoTurnHelper-$ARCH" "$BUILD/engine-$ARCH"; do
   [ -x "$COMPONENT" ] && [ "$("$LIPO" -archs "$COMPONENT")" = "$ARCH" ] || { echo 'UI-only rebuild requires a previous complete build'; exit 1; }
  done
 fi
done
APPS=(); HELPERS=(); ENGINES=()
for ARCH in $ARCHS; do APPS+=("$BUILD/AutoTurn-$ARCH"); HELPERS+=("$BUILD/AutoTurnHelper-$ARCH"); ENGINES+=("$BUILD/engine-$ARCH"); done
"$LIPO" -create "${APPS[@]}" -output "$APP/Contents/MacOS/AutoTurn"
"$LIPO" -create "${HELPERS[@]}" -output "$APP/Contents/Library/LaunchServices/AutoTurnHelper"
"$LIPO" -create "${ENGINES[@]}" -output "$APP/Contents/Resources/amneziawg-go"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -s "$ROOT/Resources/update-public-key.txt" ]; then /usr/libexec/PlistBuddy -c "Set :ATUpdatePublicKey $(cat "$ROOT/Resources/update-public-key.txt")" "$APP/Contents/Info.plist"; fi
cp "$ROOT/Resources/install-service.sh" "$APP/Contents/Resources/"
cp "$ENGINE_SOURCE/LICENSE" "$APP/Contents/Resources/AmneziaWG-LICENSE.txt"
printf '%s\n' 'v3.1.20260828 b5928efb6ca19f0153958460c3d141f04abc5c2e' > "$APP/Contents/Resources/engine-provenance.txt"
chmod +x "$APP/Contents/Resources/install-service.sh"
/usr/bin/codesign --force --sign - --identifier ru.hl100.autoturn.engine "$APP/Contents/Resources/amneziawg-go"
/usr/bin/codesign --force --sign - --identifier ru.hl100.autoturn.helper "$APP/Contents/Library/LaunchServices/AutoTurnHelper"
/usr/bin/codesign --force --sign - --identifier ru.hl100.autoturn "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
echo "$APP"
