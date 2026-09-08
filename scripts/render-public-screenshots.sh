#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/checks docs/public/assets/screenshots
frameworks=(.build/artifacts/*/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework(N))
(( ${#frameworks} == 1 )) || { print -u2 'Build the app first to fetch Sparkle'; exit 1; }
framework_parent="${frameworks[1]:h}"
source_files=(Sources/CodexUsage/*.swift)
source_files=("${(@)source_files:#Sources/CodexUsage/App.swift}")
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/.build/ModuleCache" -F "$framework_parent" -framework Sparkle -Xlinker -rpath -Xlinker "$framework_parent" "${source_files[@]}" Tests/PublicScreenshots.swift -o .build/checks/PublicScreenshots
.build/checks/PublicScreenshots
