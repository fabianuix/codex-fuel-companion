#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
mkdir -p .build/checks dist
swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c release
release_binary="$PWD/.build/release/CodexUsage"
sparkle_frameworks=(.build/artifacts/*/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework(N))
(( ${#sparkle_frameworks} == 1 )) || { print -u2 'Sparkle framework missing'; exit 1; }
sparkle_framework="${sparkle_frameworks[1]}"
sparkle_parent="${sparkle_framework:h}"
if [[ "${1:-}" == "--universal" ]]; then
    # Compile the Intel slice explicitly: newer SwiftPM build engines can ignore
    # --triple for native macOS projects. Verify both slices before packaging.
    xcrun swiftc -O -whole-module-optimization -swift-version 5 -target x86_64-apple-macos15.0 -module-cache-path "$PWD/.build/ModuleCache" -F "$sparkle_parent" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks Sources/CodexUsage/*.swift -o .build/checks/CodexFuel-intel
    lipo -create "$release_binary" .build/checks/CodexFuel-intel -output .build/checks/CodexFuel-universal
    architectures="$(lipo -info .build/checks/CodexFuel-universal)"
    [[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]] || { print "Missing release architecture"; exit 1; }
    release_binary="$PWD/.build/checks/CodexFuel-universal"
fi
xcrun swiftc -module-cache-path "$PWD/.build/ModuleCache" scripts/render-assets.swift -o .build/checks/render-assets
.build/checks/render-assets "$PWD"
iconset="$PWD/.build/CodexFuel.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -z "$doubled" "$doubled" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
app="$PWD/dist/Codex Fuel.app"
if [[ "${1:-}" == "--dev" ]]; then
    app="$PWD/dist/Codex Fuel Dev.app"
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$release_binary" "$app/Contents/MacOS/CodexUsage"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
mkdir -p "$app/Contents/Frameworks"
ditto "$sparkle_framework" "$app/Contents/Frameworks/Sparkle.framework"
cp "${sparkle_parent:h:h}/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexUsage</string>
<key>CFBundleIdentifier</key><string>local.codex.usage.menubar</string>
<key>CFBundleName</key><string>Codex Fuel</string>
<key>CFBundleDisplayName</key><string>Codex Fuel</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 fabianuix. All rights reserved.</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${CODEX_FUEL_BUILD_NUMBER:-1}" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${CODEX_FUEL_VERSION:-1.0}" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUFeedURL string https://raw.githubusercontent.com/fabianuix/codex-fuel-companion/main/appcast.xml' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUPublicEDKey string /hM4u3YzDKY4mTDKY670ahi58Mk0nIFU+ZU8rPssNB4=' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUEnableAutomaticChecks bool true' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUAutomaticallyUpdate bool true' "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUEnableInstallerLauncherService bool true' "$app/Contents/Info.plist"
if [[ "${1:-}" == "--dev" ]]; then
    dev_build=$(( $(cat .build/dev-build-number 2>/dev/null || print 0) + 1 ))
    print "$dev_build" > .build/dev-build-number
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier local.codex.usage.menubar.dev" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName Codex Fuel Dev" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Codex Fuel Dev" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $dev_build" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :CodexFuelDevelopmentBuild bool true" "$app/Contents/Info.plist"
fi
sign_options=(--force --sign "${CODEX_FUEL_SIGN_IDENTITY:--}")
if [[ -n "${CODEX_FUEL_SIGN_IDENTITY:-}" ]]; then sign_options+=(--options runtime --timestamp); fi
sparkle_embedded="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in "$sparkle_embedded"/XPCServices/*.xpc "$sparkle_embedded/Updater.app" "$sparkle_embedded/Autoupdate" "$app/Contents/Frameworks/Sparkle.framework"; do
    codesign "${sign_options[@]}" --preserve-metadata=entitlements "$nested"
done
if [[ -n "${CODEX_FUEL_SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$CODEX_FUEL_SIGN_IDENTITY" "$app"
else
    codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"
print "Built: $app"
