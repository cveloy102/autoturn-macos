# AutoTurn 0.1.6 (build 7) — validation

Published release: https://github.com/cveloy102/autoturn-macos/releases/tag/macos-v0.1.6

Changes: location settings navigation and pending home-network field refresh; full HL100 menu label; LaunchServices login registration and legacy migration; save current settings after asynchronous mode changes instead of overwriting a newer login preference. Failure to load Keychain settings now stops startup instead of persisting defaults.

Local checks passed: 92 core checks, 13 service checks, universal build, strict code signature checks, AppKit UI checks including pending SSID field updates and HL100 width, helper/engine smoke and authenticated IPC. Rendered menu and home panel reviewed. Login registration tests use isolated temporary directories.

Source CI passed on Intel macOS 15 and native ARM macOS 14/15:
https://github.com/cveloy102/autoturn-macos/actions/runs/38135187316

The exact published ZIP passed native smoke checks on all three runners:
https://github.com/cveloy102/autoturn-macos/actions/runs/38135683343
ARM checks run without Rosetta and cover UI, helper, AmneziaWG engine and signed IPC. They do not establish a connection to a real VPN server or test a particular user's Wi-Fi permissions.

The installed 0.1.5 successfully discovered signed 0.1.6 build 7 metadata and downloaded the archive with SHA-256 and Ed25519 verification. This command did not install the update or change network configuration. Logs: work/github-release/installed-feed-016.log.

The installed app was left at 0.1.5 so the user can exercise the manual updater. Actual navigation to macOS location settings, startup after logout/reboot, settings preservation through this update, and live Wi-Fi/VPN transitions remain to be verified after the user updates. The user reported re-enabling launch at login before this release; current registration alone is not evidence that the previous setting persisted.

## Post-update live checks, 2026-10-11

User installed 0.1.6 through the updater. Installed version confirmed. LaunchAgent uses LaunchServices, RunAtLoad enabled. A real logout/reboot was not performed.

Initial automatic mode connected VPN because Wi-Fi SSID was unavailable. macOS app logs reported location authorization NotDetermined. User granted permission through the new settings navigation; the running app changed to home/guard=false without restart. Direct HTTPS succeeded. Ad-hoc signing uses a cdhash designated requirement, which changes between builds; location authorization therefore cannot be assumed to survive updates.

Installed x86_64 app smoke passed. Actual installed app mode sequence on -> auto(home) -> on -> off -> auto(home) passed both curl and native URLSession HTTPS in each mode; automatic home state held 12 seconds twice. Saved settings fingerprint before and after all mode/network tests matched exactly. This verifies the tests preserved the current settings, not an exact comparison to 0.1.5 before the user's later preference edits.

User switched to the designated alternate Wi-Fi: auto connected with guard=true, known non-home SSID, both full IPv4 split routes through utun, HTTPS 200. User returned home: auto home/guard=false, no split VPN routes or engine process, DNS returned to the router, no AutoTurn SystemConfiguration keys, curl HTTPS 200 and separate native URLSession HTTPS passed. A subsequent brief physical disconnect was observed as waiting/guard=true, followed by home/guard=false after reconnection.

Logs: work/github-release/live-016.log, observe-016.log, handover-016.log, installed-smoke-016.log. These local logs are not public artifacts.

Prepared an unpublished UI change: request initial location permission when saved automatic home detection starts; clearly describe missing permission in panel/menu and provide a menu settings action. Universal UI build and AppKit UI self-check passed. This source change was not installed over the user's 0.1.6 and has not been released.
