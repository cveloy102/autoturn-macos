# AutoTurn 0.1.8 / build 9

Release: https://github.com/cveloy102/autoturn-macos/releases/tag/macos-v0.1.8
Commit: 42a7c8bb4db84533696c235d0a6c5acbc172b214

ApplicationArtwork loads the bundled ICNS directly and supplies every app-owned confirmation/information alert. Application startup explicitly assigns NSApp.applicationIconImage before loading Keychain settings, including early error dialogs. CFBundleIconFile now names AutoTurn.icns explicitly. The privileged installer touches the replaced application folder so file metadata observers can refresh Finder/Launchpad artwork.

Local: universal build, 92 core checks, 13 service checks, native Intel UI/helper/engine/signed IPC smoke all passed. UI checks require bundled artwork, a non-template alert icon and the actual alert icon instance. Real NSAlert layout rendered locally with the expected A artwork; rendering did not show a modal or alter settings/network. The captured layout is a programmatic preview, not a screenshot of a live user dialog.

Full source CI succeeded on Intel macOS 15 and native ARM macOS 14/15:
https://github.com/cveloy102/autoturn-macos/actions/runs/38140789792

Exact published ZIP native smoke succeeded on all three hosts:
https://github.com/cveloy102/autoturn-macos/actions/runs/38143239135

Installed 0.1.7 discovered 0.1.8/build 9 and verified downloaded ZIP SHA-256 and Ed25519 signatures. Before/after saved-settings fingerprints matched. No update installed locally; user requested updating via the application button.

Finder/Launchpad visual refresh on the user's machine still requires post-update observation. System-owned Keychain/location dialogs control their own icon caching; explicit NSAlert artwork applies to app-owned dialogs only. ARM checks do not establish a real VPN connection.
