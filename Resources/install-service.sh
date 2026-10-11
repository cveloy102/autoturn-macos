#!/bin/sh
set -eu
APP=$1
OWNER_UID=$2
case "$OWNER_UID" in ''|*[!0-9]*) exit 1;; esac
[ "$(id -u)" = 0 ] || { echo 'Administrator authorization is required.'; exit 1; }
[ -d "$APP" ] && [ ! -L "$APP" ]
/usr/bin/codesign --verify --deep --strict "$APP"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = 'ru.hl100.autoturn' ]
SUPPORT='/Library/Application Support/AutoTurn'
LABEL='ru.hl100.autoturn.helper'
/bin/mkdir -p "$SUPPORT" /Applications
/usr/sbin/chown root:wheel "$SUPPORT"
/bin/chmod 700 "$SUPPORT"
# Stage immutable, root-owned copies before trusting manifest hashes.
STAGE="$SUPPORT/stage-$$.app"
/usr/bin/ditto "$APP" "$STAGE"
/usr/sbin/chown -R root:wheel "$STAGE"
/bin/chmod -R go-w "$STAGE"
/usr/bin/codesign --verify --deep --strict "$STAGE"
HASHES=''
for ARCH in x86_64 arm64; do
 HASH=$(/usr/bin/codesign --display --verbose=4 --arch "$ARCH" "$STAGE" 2>&1 | /usr/bin/awk -F= '/^CDHash=/{print $2}')
 if [ -n "$HASH" ]; then
  case "$HASH" in *[!a-f0-9]*|'') exit 1;; esac
  if [ -n "$HASHES" ]; then HASHES="$HASHES,"; fi
  HASHES="$HASHES\"$HASH\""
 fi
done
[ -n "$HASHES" ]
# Do not call stop: PF protection survives replacement of the helper.
/bin/launchctl bootout "system/$LABEL" >/dev/null 2>&1 || true
/bin/cp "$STAGE/Contents/Library/LaunchServices/AutoTurnHelper" "$SUPPORT/AutoTurnHelper.new"
/bin/cp "$STAGE/Contents/Resources/amneziawg-go" "$SUPPORT/amneziawg-go.new"
/bin/cp "$STAGE/Contents/Resources/routing-core" "$SUPPORT/routing-core.new"
/bin/chmod 755 "$SUPPORT/AutoTurnHelper.new" "$SUPPORT/amneziawg-go.new" "$SUPPORT/routing-core.new"
/bin/mv -f "$SUPPORT/AutoTurnHelper.new" "$SUPPORT/AutoTurnHelper"
/bin/mv -f "$SUPPORT/amneziawg-go.new" "$SUPPORT/amneziawg-go"
/bin/mv -f "$SUPPORT/routing-core.new" "$SUPPORT/routing-core"
cat > "$SUPPORT/installation.json.new" <<EOF
{"uid":$OWNER_UID,"cdhashes":[$HASHES],"engine":"/Library/Application Support/AutoTurn/amneziawg-go"}
EOF
/bin/chmod 600 "$SUPPORT/installation.json.new"
/bin/mv -f "$SUPPORT/installation.json.new" "$SUPPORT/installation.json"
if [ -d /Applications/AutoTurn.app ]; then
 /bin/mv /Applications/AutoTurn.app "$SUPPORT/previous-$(date +%Y%m%d-%H%M%S)-$$.app"
fi
/bin/mv "$STAGE" /Applications/AutoTurn.app
# New folder timestamp invalidates Finder/Launchpad artwork cached for this path.
/usr/bin/touch /Applications/AutoTurn.app
cat > "/Library/LaunchDaemons/$LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$LABEL</string>
<key>ProgramArguments</key><array><string>$SUPPORT/AutoTurnHelper</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>10</integer>
<key>ProcessType</key><string>Background</string>
<key>Umask</key><integer>63</integer>
</dict></plist>
EOF
/usr/sbin/chown root:wheel "/Library/LaunchDaemons/$LABEL.plist"
/bin/chmod 644 "/Library/LaunchDaemons/$LABEL.plist"
/bin/launchctl bootstrap system "/Library/LaunchDaemons/$LABEL.plist"
/bin/launchctl kickstart "system/$LABEL"
echo 'AutoTurn VPN service installed.'
