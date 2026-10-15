#!/bin/bash
# Read-only macOS snapshot. No VPN profile, Keychain or routing-core config is read.
set -u
if [ "$(uname -s)" != Darwin ]; then
  echo 'Run this script on the affected Mac.' >&2
  exit 1
fi
umask 077
OUTPUT="$HOME/Desktop/AutoTurn-network-$(date +%Y%m%d-%H%M%S).txt"
echo 'Administrator access is needed only to read the AutoTurn PF rules and events.'
sudo -v || exit 1
{
  echo '=== Capture time / OS / process architecture ==='
  date
  date -u
  sw_vers
  uname -m
  sysctl -n hw.model
  sysctl -n hw.machine
  sysctl -n sysctl.proc_translated 2>/dev/null || true
  uptime
  echo '=== Installed app version ==='
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/AutoTurn.app/Contents/Info.plist
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' /Applications/AutoTurn.app/Contents/Info.plist
  echo '=== AutoTurn service ==='
  sudo launchctl print system/ru.hl100.autoturn.helper
  echo '=== PF status and AutoTurn anchor (read only) ==='
  sudo /sbin/pfctl -s info
  sudo /sbin/pfctl -a com.apple/autoturn -sr
  echo '=== Routes ==='
  netstat -rn
  echo '=== DNS ==='
  scutil --dns
  echo '=== System proxies ==='
  scutil --proxy
  echo '=== Persisted AutoTurn events (if supported by this version) ==='
  sudo /bin/cat '/Library/Application Support/AutoTurn/events.json'
  echo
  echo '=== Bounded direct HTTPS probes; no proxy ==='
  for TARGET in https://example.com https://www.apple.com/library/test/success.html; do
    echo "$TARGET"
    /usr/bin/curl -4 -I --noproxy '*' --connect-timeout 3 --max-time 7 "$TARGET"
  done
} > "$OUTPUT" 2>&1
echo "Saved: $OUTPUT"
echo 'Send this file privately together with the app diagnostic export. Capture BEFORE choosing Off or recovery.'
