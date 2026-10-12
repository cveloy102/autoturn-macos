# AutoTurn macOS 0.1.5 / build 6

- Local core tests: 84 passed; helper/service tests: 13 passed.
- Local native x86_64 smoke passed: universal architectures, strict signatures, native app UI with live popover update and outside-click dismissal, helper, AmneziaWG 3.1 engine, authenticated signed IPC client and rejected other client.
- Source CI passed on Intel/macOS 15 and Apple Silicon/macOS 14 and 15: https://github.com/cveloy102/autoturn-macos/actions/runs/38133179679
- Exact published ZIP passed native app/helper/engine/IPC smoke on all three machines: https://github.com/cveloy102/autoturn-macos/actions/runs/38133620715
- Public source: https://github.com/cveloy102/autoturn-macos
- Page: https://cveloy102.github.io/autoturn-macos/
- Release: https://github.com/cveloy102/autoturn-macos/releases/tag/macos-v0.1.5
- Actual Updater recognized build 6 with installed-build override 5; downloaded ZIP from GitHub, verified SHA-256 and Ed25519. Without override it reported installed version current.
- Downloaded bundle signature and all three universal components verified, actual installer updated /Applications and root helper successfully.
- SHA-256 of canonical saved settings before/after installation matched exactly; no profile data printed.
- Actual installed app, launched through LaunchServices: on -> auto(home) -> on -> off -> auto(home) passed; curl and native URLSession HTTPS succeeded in every mode, home held for 12 seconds twice. Final mode auto at home.
- Direct terminal launch initially could not read SSID; LaunchServices launch identified home immediately and passed the full test. No permission bypass used.

Unit tests cover 24-hour schedule, retry, clock changes, persisted history, notification deduplication and signature tampering. Actual future-version notification delivery is not proven by the current-version feed test.
Runtime CI verifies architecture and component integration without VPN credentials. The recipient's real VPN server and Wi-Fi network on their M1 remain to be checked separately.
