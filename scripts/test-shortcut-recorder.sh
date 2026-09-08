#!/bin/zsh
set -euo pipefail
setopt extendedglob
cd "${0:A:h:h}"
frameworks=(.build/artifacts/*/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework(N))
(( ${#frameworks} == 1 )) || { print -u2 'Run scripts/build.sh --dev first'; exit 1; }
framework="${frameworks[1]}"
mkdir -p .build/checks
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/.build/ModuleCache" -F "${framework:h}" -framework Sparkle -Xlinker -rpath -Xlinker "$PWD/${framework:h}" -parse-as-library Sources/CodexUsage/*.swift~Sources/CodexUsage/App.swift Tests/ShortcutRecorderTests.swift -o .build/checks/ShortcutRecorderTests
.build/checks/ShortcutRecorderTests
