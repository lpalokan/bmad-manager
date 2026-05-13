# BMad Manager

A small macOS app that creates new project folders pre-configured with the
[BMad method](https://github.com/bmadcode/bmad-method) for Claude Code and
opencode, and installs a custom "marketing growth" module on top.

The UI is intentionally tiny:

- Pick a project root folder and a marketing-growth `.zip` (one-time setup in Settings).
- Type a new project name, click **Create new project**.
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
  created. Available placeholders:
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
Resources/Info.plist
scripts/build_release.sh
```

## How a project gets created

1. Validate the typed name (non-empty, no `/`, no leading `.`, not already present).
2. `mkdir <projectsRoot>/<name>`.
3. If a module zip is configured: extract it to a fresh
   `/tmp/bmad-manager-<uuid>/` using `/usr/bin/unzip`.
4. Substitute placeholders in the init command.
5. Run the command in `/bin/zsh -lc '...'` with the project folder as the
   working directory (so `npx`, Homebrew, nvm, etc. resolve from your shell PATH).
   Output streams into the bottom panel.
6. Clean up the `/tmp` extraction directory.

On failure the partial project folder is kept so you can inspect it; delete it
from the list with the trash button when you're done.
