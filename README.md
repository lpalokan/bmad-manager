# BMad Manager

[![build](https://github.com/lpalokan/bmad-manager/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/lpalokan/bmad-manager/actions/workflows/build.yml)

A small macOS app that creates new project folders pre-configured with the
[BMad method](https://github.com/bmadcode/bmad-method) for Claude Code and
opencode, and installs a custom "marketing growth" module on top.

The UI is intentionally tiny:

- Pick a project root folder (one-time setup in Settings).
- Type a new project name, click **Create new project**.
- The first time you create a project without a marketing-growth `.zip`
  configured, the app pops a file picker, remembers your choice, and continues.
- Each project row has buttons to open it in Claude Code or opencode in a
  Terminal window, plus a trash button (moves to macOS Trash).

## End-user install

You receive **`bmad-manager.dmg`** from the developer.

1. Double-click the DMG.
2. Drag `bmad-manager.app` onto the `Applications` shortcut.
3. First launch only: right-click `bmad-manager` in `/Applications` → **Open**,
   then click **Open** in the Gatekeeper warning. (The app is ad-hoc signed,
   not notarized — this one-time step is normal for indie macOS apps.)
4. The first time you click "Claude Code" or "opencode" on a project, macOS
   will ask permission for the app to control Terminal. Click **OK**.

Settings (cogwheel icon) let you change:

- **Projects root folder** — every new project becomes a subfolder here.
- **Marketing growth module (.zip)** — the latest module package on disk.
- **Init command** — the headless command run after the project folder is
  created. The default uses the BMad [headless install
  flags](https://docs.bmad-method.org/how-to/install-bmad/#headless-ci-installs)
  (`--yes --modules bmm,bmb,cis --tools claude-code,opencode --custom-source ... --directory ...`)
  to install the BMad Method core, BMad Builder, and Creative Intelligence
  Suite configured for both Claude Code and opencode, and to register the
  unzipped marketing-growth bundle as a proper BMad module via
  `--custom-source` (rather than overlaying its files on the project). When
  the bundle is a GitHub "Download ZIP" archive, the app auto-descends into
  the single wrapper folder so `--custom-source` sees the module root. If
  you're upgrading an existing install, hit **Reset to defaults** so your
  persisted command picks up the current flags. Available placeholders:
  - `{PROJECT_PATH}` — absolute path of the new project folder
  - `{MODULE_PATH}` — absolute path of the unzipped module (in `/tmp/...`)
  - `{PROJECT_NAME}` — bare folder name
- **Claude Code / opencode commands** — the binaries (or aliases) invoked by
  the per-row launch buttons.

Defaults are restored via **Reset to defaults** in Settings. Configuration is
persisted at `~/Library/Application Support/bmad-manager/settings.json`.

## Developer build

Requirements: macOS with Xcode (or Command Line Tools), Swift 5.9+. No
`.xcodeproj` is used — everything builds from the terminal via SwiftPM.

```sh
./scripts/build_release.sh
```

That produces `dist/bmad-manager.dmg`. Share that single file with end users.

The script:

1. `swift build -c release --arch arm64 --arch x86_64` (universal binary;
   falls back to host arch if the multi-arch flags aren't supported).
2. Wraps the binary into `build/bmad-manager.app` with `Resources/Info.plist`.
3. Ad-hoc codesigns the bundle (`codesign --sign -`) — no paid Apple
   Developer ID required.
4. Wraps the `.app` plus an `Applications` symlink into `dist/bmad-manager.dmg`
   via `hdiutil`.

To iterate while developing without producing the DMG:

```sh
swift run
```

### Signed + notarized releases (optional)

Default behavior is fine for personal use — end users right-click → Open the
first time to bypass Gatekeeper. To skip that step entirely (paid Apple
Developer ID required), set two environment variables:

```sh
APPLE_DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE="my-notary-profile" \
./scripts/build_release.sh
```

One-time setup for `NOTARY_PROFILE`:

```sh
xcrun notarytool store-credentials "my-notary-profile" \
    --apple-id "you@example.com" \
    --team-id "TEAMID" \
    --password "your-app-specific-password"
```

If only `APPLE_DEVELOPER_ID` is set (no `NOTARY_PROFILE`), the app is signed
but not notarized — Gatekeeper will still warn. Set both for a clean
double-click experience.

### Running tests

```sh
swift test
```

Covers `AppSettings`, `ProjectService`, `ZipExtractor`, and the
`TerminalLauncher` escaping helpers. Tests are macOS-only (the package
platform is `.macOS(.v14)`).

## Project layout

```
Package.swift
Sources/BmadManager/
    BmadManagerApp.swift          # @main App
    Models/                       # AppSettings, ProjectItem
    Services/                     # SettingsStore, ProjectService,
                                  # ZipExtractor, CommandRunner, TerminalLauncher
    Views/                        # ContentView, ProjectRowView,
                                  # SettingsView, CommandOutputView
Resources/
    Info.plist
    icon-source.png               # 1024x1024 source for the app icon
scripts/
    build_release.sh
    make_icon.sh                  # turns icon-source.png into AppIcon.icns (macOS sips + iconutil)
```

The `.icns` and `.iconset` are generated at build time (via `scripts/make_icon.sh`,
which `build_release.sh` calls automatically when the `.icns` is missing) and are
git-ignored. To regenerate after editing `icon-source.png`, just rerun the build
script or call `./scripts/make_icon.sh` directly.

## How a project gets created

1. Validate the typed name (non-empty, no `/`, no leading `.`, not already present).
2. If no marketing-growth `.zip` is configured, pop a file picker, save the
   choice to settings, then continue.
3. `mkdir <projectsRoot>/<name>`.
4. Extract the module zip to a fresh `/tmp/bmad-manager-<uuid>/` using `/usr/bin/unzip`.
5. Substitute placeholders in the init command.
6. Run the command in `/bin/zsh -lc '...'` with the project folder as the
   working directory (so `npx`, Homebrew, nvm, etc. resolve from your shell PATH).
   Output streams into the bottom panel.
7. Clean up the `/tmp` extraction directory.

On failure the partial project folder is kept so you can inspect it; delete it
from the list with the trash button when you're done.
