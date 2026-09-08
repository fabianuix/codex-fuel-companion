# Build Codex Fuel

This repository contains the source snapshot for the release identified in
`SOURCE.json`. Development changes are published here only with an intentional
public update.

## Requirements

- A Mac running macOS 15 or later.
- Xcode command-line tools with Swift 6 or later.
- Python 3, available as `python3` in Terminal.
- Internet access for the pinned Sparkle dependency.

Open **Terminal** (in Applications → Utilities). If the command-line tools
aren't installed, run `xcode-select --install` and complete the installation.
Check that the tools are available:

```sh
swift --version
python3 --version
git --version
```

Swift should report version 6 or later. If it's older, update Xcode or its
command-line tools before continuing. If Python is missing, install Python 3
from [python.org](https://www.python.org/downloads/macos/).

## Get the source

```sh
git clone https://github.com/fabianuix/codex-fuel-companion.git
cd codex-fuel-companion
```

Alternatively, open the [latest release](https://github.com/fabianuix/codex-fuel-companion/releases/latest),
download the file ending in **-source.zip**, and unzip it. In Terminal, type
`cd ` (including the space), drag the extracted
folder from Finder into Terminal, and press Return. Choose the folder containing
`Package.swift`, `SOURCE.json`, and `scripts`.

## Run a development build

From the repository folder:

```sh
export CODEX_FUEL_VERSION="$(python3 -c 'import json; print(json.load(open("SOURCE.json"))["version"])')"
./scripts/test.sh
./scripts/build.sh --dev
open "dist/Codex Fuel Dev.app"
```

The checks print `PASS` messages. A successful build ends with `Built:` and the
app's location. You can also open the **dist** folder in Finder and double-click
**Codex Fuel Dev.app**. It lives in the menu bar, so no Dock icon or normal app
window appears automatically. Click its menu-bar icon to open the panel.

The development app has its own identity and preferences. It does not replace
the installed release or install release updates. Sign in to Codex or the Codex
CLI to use live account data. Quit the release app while testing the same global
keyboard shortcut.

No paid Apple Developer account, signing certificate, or release-publishing
credentials are needed for this local development build.

## If something goes wrong

- **“No such file or directory”:** make sure Terminal is in the extracted or
  cloned folder containing `Package.swift` before running the build commands.
- **“Permission denied” after unzipping:** run `chmod +x scripts/*.sh`, then retry.
- **A dependency download fails:** check your internet connection and rerun the
  build. The required Sparkle version is downloaded automatically.
- **The app opens but shows no account:** sign in to Codex or the Codex CLI,
  then refresh the panel.
- **The keyboard shortcut opens the other app:** quit the regular Codex Fuel
  app while using Codex Fuel Dev.

To rebuild after editing the source, quit the running development app, run
`./scripts/build.sh --dev` again, and reopen the newly built copy.

## Additional checks

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
