#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$ROOT/.build"
if [ -x /Library/Developer/CommandLineTools/usr/bin/swiftc ]; then
 SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc
 SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
else
 SWIFTC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
 SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
fi
"$SWIFTC" -sdk "$SDK" "$ROOT/Sources/Shared/Model.swift" "$ROOT/Sources/App/Updates.swift" "$ROOT/Sources/App/UpdateSchedule.swift" "$ROOT/Sources/App/LoginRegistration.swift" "$ROOT/Tests/main.swift" -framework CryptoKit -o "$ROOT/.build/core-tests"
"$ROOT/.build/core-tests"
bash -n "$ROOT/scripts/build.sh"
sh -n "$ROOT/Resources/install-service.sh"

"$SWIFTC" -sdk "$SDK" "$ROOT"/Sources/Shared/*.swift "$ROOT/Sources/Helper/Networking.swift" "$ROOT/Sources/Helper/Service.swift" "$ROOT/TestsService/main.swift" -framework Network -framework SystemConfiguration -o "$ROOT/.build/service-tests"
"$ROOT/.build/service-tests"
