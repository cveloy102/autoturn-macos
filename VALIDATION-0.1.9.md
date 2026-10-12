# AutoTurn 0.1.9 (build 10)

Local implementation: default console / instrument menu, independent UserDefaults appearance choices, hourly signed update checks, version-level notification history, persistent signed release indicator, direct installation action from both UI surfaces.

Core: 94 assertions, including hourly boundary, persisted schedule and same-version/new-build notification deduplication. Service: 13 transition checks; network behavior unchanged.

Universal x86_64/arm64 UI build plus previously validated unchanged helper/engine slices. Local native x86_64 smoke checks include all six appearances, update UI, five tabs, popover live refresh and outside clicks, helper/engine launch, approved and denied IPC clients. Final rebuilt smoke result is recorded in work/github-release/smoke-menu-hourly.log.

No installation over /Applications, saved VPN profile mutation, real network switches or notification delivery performed in this validation. arm64 launch and this version's GitHub release are not yet verified/published.

Final package: dist/AutoTurn-0.1.9-macOS.zip created with signed macos-update.json. The extracted ZIP passed strict codesign/lipo and full native Intel smoke again (work/github-release/smoke-zip-019.log).

Responsiveness: native AppKit scrolling and 0.12-second section fades; Reduce Motion respected. No fixed display FPS timer. State-only polling skips redundant layouts and reuses template artwork. In local self-check, 1000 unchanged UI updates averaged 0.006–0.013 ms each; this measures synchronous UI work, not rendered FPS. No ProMotion display test performed. See Apple's Improving app responsiveness documentation for AppKit display-rate adaptation.

Full-screen menu fix: replaced the attached NSPopover with StableMenuPanel (borderless nonactivating NSPanel, canJoinAllSpaces/fullScreenAuxiliary). Captures the opening screen position once, preserves its top/right when content updates, clips oversized menus with native scrolling, Escape dismisses the panel. Opening no longer activates the main console. Existing outside-click and monitor-cleanup tests pass.

Native regression: move the status item's anchor window by 60 points while the menu is open; verify the panel stays visible at the same frame; force live status refresh and verify the top/right anchor remains fixed. Native Intel smoke after this change passed (work/github-release/smoke-fullscreen-menu.log). Manual interaction in an actual foreign full-screen app has not been performed. No installed app replacement, Keychain or VPN state changes.

Published 2026-10-11: https://github.com/cveloy102/autoturn-macos/releases/tag/macos-v0.1.9 at commit a7900e9019dee18a58d504b6eb08c3ba3369514d. Uploaded ZIP SHA-256 ca957edfdcb4172c32cdbb4715352e2f8ed05b1e87ea7b6080ac235b0a87278c matches the final local package. Final local extracted package smoke: work/github-release/smoke-zip-019-fullscreen.log.

Published archive workflow 38148804547 passed all three native jobs: macos-14 ARM, macos-15 ARM and macos-15-intel. Source build/smoke passed both ARM jobs; Intel source rebuild was still running at this check. Published ZIP has already passed the native Intel runtime smoke independently.

Installed /Applications/AutoTurn.app successfully discovered version 0.1.9 build 10 and downloaded the GitHub ZIP, verifying SHA-256 and Ed25519 without installation or VPN/network changes (work/github-release/installed-feed-019.log). Pages deployment passed. No physical M1 MacBook Pro or 120 Hz/full-screen interaction test was performed.
