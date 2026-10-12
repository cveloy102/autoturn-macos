# AutoTurn 0.1.7 (build 8)

Published release: https://github.com/cveloy102/autoturn-macos/releases/tag/macos-v0.1.7
Source/tag commit: a637bd59aa3db379af9846d0da0cc23bb2f5a325

Approved icon set A implemented: original Android A geometry and RGB palette in a macOS rounded-square ICNS with ten standard/Retina sizes; template status icons at 18 pt for home router, verified VPN shield/check, connecting/retry arrows, error shield/exclamation, manual off crossed shield and unknown network question mark. Adjacent status glyphs removed. A verified shield appears only for the helper's connected state.

The previously prepared Wi-Fi permission fix is included: request initial authorization for automatic mode with saved home networks, describe missing permission in panel/menu, offer a settings action in the menu, and include the description in menu refresh state. A denied permission remains the user's choice; no system privacy database changes are made.

Local checks: 92 core and 13 service checks passed; universal build passed; native x86_64 UI/helper/engine/signed IPC smoke passed; icon template dimensions, rasterization, distinct shapes and home/VPN/unknown mapping checked. ICNS extraction produced all ten expected assets; generated application icon visually reviewed. Final bundle deep/strict signature verified after icon RGB adjustment.

Installed 0.1.6 discovered signed 0.1.7/build 8 metadata and downloaded the exact GitHub ZIP. SHA-256 and Ed25519 verification passed. Installed app remains 0.1.6; its saved settings fingerprint before/after feed/download testing matched. No installation or live network settings changed in this release task.

Source CI: https://github.com/cveloy102/autoturn-macos/actions/runs/38139442000
Source CI ARM macOS 14/15 succeeded; Intel hosted build was still running at handoff. Local Intel universal build and exact published ZIP execution on hosted Intel both passed.
Exact published ZIP CI: https://github.com/cveloy102/autoturn-macos/actions/runs/38139536084

Exact ZIP native smoke succeeded on Intel macOS 15 and ARM macOS 14/15. Tests execute app UI (including all status icons), helper, engine, authenticated IPC and rejection of an unapproved IPC client. ARM execution is native, without Rosetta.

Post-install testing on the user's Mac is deferred until the user updates through the application button, as requested. ARM runners do not have real VPN credentials or the recipient's Wi-Fi environment.
