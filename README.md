# BMad Manager

[![build](https://github.com/lpalokan/bmad-manager/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/lpalokan/bmad-manager/actions/workflows/build.yml)
[![tauri-windows-check](https://github.com/lpalokan/bmad-manager/actions/workflows/tauri-windows-check.yml/badge.svg?branch=main)](https://github.com/lpalokan/bmad-manager/actions/workflows/tauri-windows-check.yml)

A small macOS app that creates new project folders pre-configured with the
[BMad method](https://github.com/bmadcode/bmad-method) for Claude Code and
opencode, and installs a custom "marketing growth" module on top.

A Windows port via Tauri is in progress under [`tauri/`](tauri/) —
see [issue #25](https://github.com/lpalokan/bmad-manager/issues/25) for the
shipping plan. Stages 1 (scaffold) and 2 (Rust ports + Svelte UI) have
landed on `main`; Stage 3 will bundle Node + PortableGit into a single
NSIS installer and ship a GitHub Release.

The UI is intentionally tiny:

- Pick a project root folder (one-time setup in Settings).
- Type a new project name, click **Create new project**.
- By default the marketing-growth module is pulled fresh from
  [github.com/lpalokan/bmad-marketing-growth](https://github.com/lpalokan/bmad-marketing-growth)
  via a shallow `git clone`. You can switch to a local `.zip` in Settings —
  if you switch to local-zip without one configured, the app pops a file
  picker, remembers your choice, and continues.
- When other projects already carry a company context
  (`_bmad-output/company-context/` with the marketing-growth module's
  recognized files — `icp.md`, `positioning.md`, `brand-voice.md`,
  `kpis.md`, `tech-stack.md`), a **Context** menu appears under the create
  row. Pick a source project to copy its context files into the new
  project right after a successful install, or leave **Start from
  scratch** selected. Imported files are copied verbatim; run the module's
  company-context-bootstrap workflow in the new project to adapt them.
- Each project row shows when it was created and has buttons to open it in
  Claude Code or opencode in a Terminal window, plus a trash button (moves
  to macOS Trash).
- A **Sort** menu above the list reorders projects by name (A→Z) or by
  creation date (newest or oldest first). The choice is persisted.

## Install via Homebrew (recommended)

```
brew install --cask lpalokan/tap/bmad-manager
xattr -r -d com.apple.quarantine /Applications/bmad-manager.app
```

The first command installs the app. The second removes the Gatekeeper
quarantine attribute Homebrew applies to downloads — without it, the
first launch needs a right-click → **Open** dance. Homebrew
[intentionally won't bypass quarantine from inside a cask](https://github.com/Homebrew/brew/issues/20755),
so this stays as a one-time user step instead of cask magic. Rerun the
`xattr` command after every `brew upgrade`, since the upgrade reinstalls
the bundle and quarantine gets reapplied. No paid Apple Developer ID
required either way.

Manual DMG install below still works if you prefer it.

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
- **Marketing growth module source** — pick one:
  - **GitHub repo** (default): a public `https://...` URL plus an optional
    branch/tag/SHA. Blank ref = follow the repo's default branch. Each
    project creation does a `git clone --depth 1` into a temp dir, so you
    always get the latest upstream. Requires `git` on PATH — Xcode Command
    Line Tools provides it (`xcode-select --install`).
  - **Local zip**: path to a `.zip` on disk. GitHub "Download ZIP" archives
    are auto-unwrapped (the app descends into the single wrapper folder so
    `--custom-source` sees the module root).
- **Init command** — the headless command run after the project folder is
  created. The default uses the BMad [headless install
  flags](https://docs.bmad-method.org/how-to/install-bmad/#headless-ci-installs)
  (`--yes --modules bmm,bmb,cis --tools claude-code,opencode,pi --custom-source ... --directory ...`)
  to install the BMad Method core, BMad Builder, and Creative Intelligence
  Suite configured for Claude Code, opencode, and Pi, and to register the
  materialised marketing-growth bundle as a proper BMad module via
  `--custom-source` (rather than overlaying its files on the project). If
  you're upgrading an existing install, hit **Reset to defaults** so your
  persisted command picks up the current flags. Available placeholders:
  - `{PROJECT_PATH}` — absolute path of the new project folder
  - `{MODULE_PATH}` — absolute path of the materialised module (in `/tmp/...`)
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

### Windows build (Tauri, in progress)

The Windows port lives under [`tauri/`](tauri/) and is being built in three
stages tracked by [issue #25](https://github.com/lpalokan/bmad-manager/issues/25):

1. **Stage 1 — scaffold** *(done)*: Tauri + Svelte project, platform module
   skeleton, BDD harnesses, Windows `cargo check` CI.
2. **Stage 2 — services + UI** *(current)*: Rust ports of `SettingsStore`,
   `ProjectService`, both `ModuleSource` adapters, `CommandRunner`,
   `ProjectCreator`; the full `platform::windows` arm; Svelte UI components
   driving them via Tauri commands.
3. **Stage 3 — bundle + release**: portable Node + PortableGit baked into the
   NSIS installer, pre-warmed `bmad-method` npm cache, GitHub Release workflow.

See [`tauri/README.md`](tauri/README.md) for prerequisites and developer
commands. End-user Windows install instructions land with Stage 3.

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

Covers `AppSettings`, `ProjectService`, both `ModuleSource` adapters
(`GitRepoModuleSource`, `LocalZipModuleSource`), `ProjectCreator`
orchestration via a fake source, `CompanyContextService` resolution and
import, the shared `Subprocess` runner, and the `TerminalLauncher`
escaping helpers. Tests are macOS-only (the package platform is `.macOS(.v14)`)
and require full Xcode (XCTest isn't shipped in the Command Line Tools
stand-alone install).

## Project layout

```
Package.swift
Sources/BmadManager/
    BmadManagerApp.swift          # @main App
    Models/                       # AppSettings, ProjectItem, CompanyContext
    Services/                     # SettingsStore, ProjectService,
                                  # CompanyContextService,
                                  # ModuleSource (+ GitRepoModuleSource,
                                  # LocalZipModuleSource), Subprocess,
                                  # CommandRunner, TerminalLauncher
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
2. If the source is **Local zip** and none is configured, pop a file picker,
   save the choice to settings, then continue. (The GitHub-repo source has a
   default URL and never prompts.)
3. `mkdir <projectsRoot>/<name>`.
4. Materialise the module into a fresh `/tmp/bmad-manager-<uuid>/`:
   - **GitHub repo**: `git clone --depth 1 [--branch <ref>] <url>` into the
     temp dir. The clone root is the module root.
   - **Local zip**: extract with `/usr/bin/unzip`, then descend into the
     single wrapper folder if the archive has GitHub's "Download ZIP" shape.
5. Substitute placeholders in the init command.
6. Run the command in `/bin/zsh -lc '...'` with the project folder as the
   working directory (so `npx`, Homebrew, nvm, etc. resolve from your shell PATH).
   Output streams into the bottom panel.
7. Clean up the `/tmp` materialisation directory.
8. If a source context was selected in the **Context** menu, copy its
   recognized files into `<project>/_bmad-output/company-context/` (files
   the init command already created there are never overwritten). This
   step is skipped when the init command failed.

On failure the partial project folder is kept so you can inspect it; delete it
from the list with the trash button when you're done.
