#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP=${1:-"$ROOT/dist/AutoTurn.app"}
ARCH=$(uname -m)
case "$ARCH" in x86_64|arm64) ;; *) echo 'Unsupported test host'; exit 1;; esac
/usr/bin/codesign --verify --deep --strict "$APP"
for COMPONENT in Contents/MacOS/AutoTurn Contents/Library/LaunchServices/AutoTurnHelper Contents/Resources/amneziawg-go Contents/Resources/routing-core; do
 /usr/bin/lipo "$APP/$COMPONENT" -verify_arch x86_64 arm64
 /usr/bin/otool -arch "$ARCH" -L "$APP/$COMPONENT"
done
"$APP/Contents/Resources/routing-core" version
"$APP/Contents/Resources/amneziawg-go" --version
"$APP/Contents/Library/LaunchServices/AutoTurnHelper" --self-check
"$APP/Contents/MacOS/AutoTurn" --ui-self-check
SOCKET="/tmp/at-smoke-$$.sock"
HASH=$(/usr/bin/codesign --display --verbose=4 --arch "$ARCH" "$APP" 2>&1 | /usr/bin/awk -F= '/^CDHash=/ {print $2}')
[ -n "$HASH" ]
"$APP/Contents/Library/LaunchServices/AutoTurnHelper" --ipc-test-server "$SOCKET" "$HASH" &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true; [ ! -S "$SOCKET" ] || unlink "$SOCKET"' EXIT
for STEP in {1..50}; do [ ! -S "$SOCKET" ] || break; sleep 0.1; done
"$APP/Contents/MacOS/AutoTurn" --ipc-test-client "$SOCKET"
wait "$SERVER_PID"
"$APP/Contents/Library/LaunchServices/AutoTurnHelper" --ipc-test-server "$SOCKET" "$HASH" &
SERVER_PID=$!
for STEP in {1..50}; do [ ! -S "$SOCKET" ] || break; sleep 0.1; done
ANSWER=$(/usr/bin/nc -w 3 -U "$SOCKET" </dev/null)
[ "$ANSWER" = denied ]
if wait "$SERVER_PID"; then echo 'Unapproved client was accepted'; exit 1; else [ "$?" = 2 ]; fi
trap - EXIT
echo "Native $ARCH smoke passed: app UI, helper, engine, signed IPC client and rejected other client. No VPN or Keychain changes."
