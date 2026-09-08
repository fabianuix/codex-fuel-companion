#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build/checks
xcrun swiftc -module-cache-path "$PWD/.build/ModuleCache" Sources/CodexUsage/Models.swift Sources/CodexUsage/CodexClient.swift Tests/CodexUsageTests/UsageTests.swift -o .build/checks/UsageTests
.build/checks/UsageTests
xcrun swiftc -module-cache-path "$PWD/.build/ModuleCache" Sources/CodexUsage/Models.swift Sources/CodexUsage/GaugeIcon.swift Sources/CodexUsage/CoinsIcon.swift Tests/GaugeTests.swift -o .build/checks/GaugeTests
.build/checks/GaugeTests
xcrun swiftc -module-cache-path "$PWD/.build/ModuleCache" Sources/CodexUsage/Models.swift Sources/CodexUsage/CodexClient.swift Sources/CodexUsage/UsageHistory.swift Sources/CodexUsage/UsageStore.swift Tests/StoreTests.swift -o .build/checks/StoreTests
.build/checks/StoreTests
xcrun swiftc -module-cache-path "$PWD/.build/ModuleCache" Sources/CodexUsage/Models.swift Sources/CodexUsage/UsageHistory.swift Tests/HistoryTests.swift -o .build/checks/HistoryTests
.build/checks/HistoryTests
