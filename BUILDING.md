# Build Codex Fuel

This repository contains the source snapshot for the release identified in
`SOURCE.json`. Development changes are published here only with an intentional
public update.

## Requirements

- A Mac running macOS 15 or later.
- Xcode command-line tools with Swift 6 or later.
- Internet access for the pinned Sparkle dependency.

## Run a development build

From the repository folder:

```sh
export CODEX_FUEL_VERSION="$(python3 -c 'import json; print(json.load(open("SOURCE.json"))["version"])')"
./scripts/test.sh
./scripts/build.sh --dev
open "dist/Codex Fuel Dev.app"
```

The development app has its own identity and preferences. It does not replace
the installed release or install release updates. Sign in to Codex or the Codex
CLI to use live account data. Quit the release app while testing the same global
keyboard shortcut.

After building, run the additional checks:

```sh
./scripts/test-update-interface.sh
./scripts/test-shortcut-recorder.sh
```

## Source layout

| Folder | Contents |
| --- | --- |
| `Sources/CodexUsage/` | App entry point, menu bar and panels, account data, usage state, notifications, and updates. |
| `Tests/` | App behavior checks and synthetic account fixtures. |
| `Resources/` | App artwork used during builds. |
| `scripts/` | Local build, test, and sample-screen tools. |
| `assets/` | Screenshots and artwork for this guide. |

`Package.swift` pins Sparkle, the update framework. Its public verification key
and public update URL are intentionally part of the build. Signing credentials
and release publishing tools are not included. Local builds are signed locally;
they are not the distributed release binary.

## Rights

Source is available for inspection under the existing [license](LICENSE).
All rights remain reserved; publishing this snapshot does not change the license
to an open-source license. Sparkle retains its own license, included in built apps.
