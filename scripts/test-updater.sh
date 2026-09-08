#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Run after build.sh --dev. This harness checks only the empty/public feed;
# it does not build an update archive or replace an installed app.
app="$PWD/.build/checks/UpdaterSmoke.app"
framework="$PWD/dist/Codex Fuel Dev.app/Contents/Frameworks/Sparkle.framework"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
cp 'dist/Codex Fuel Dev.app/Contents/Info.plist' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Delete :CodexFuelDevelopmentBuild' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.codex.fuel.updater-smoke' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable UpdaterSmoke' "$app/Contents/Info.plist"
# Never install an update in this test even after public releases exist.
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 999999999' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :SUAutomaticallyUpdate false' "$app/Contents/Info.plist"
ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
xcrun swiftc -swift-version 5 -module-cache-path "$PWD/.build/ModuleCache" -F "${framework:h}" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks Sources/CodexUsage/AppUpdater.swift Tests/UpdaterSmoke.swift -o "$app/Contents/MacOS/UpdaterSmoke"
codesign --force --sign - "$app"
"$app/Contents/MacOS/UpdaterSmoke"
