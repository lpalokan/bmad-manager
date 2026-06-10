# BMad Manager — Tauri (Windows-first)

Cross-platform port of the Swift macOS app under [`Sources/BmadManager/`](../Sources/BmadManager).
The Tauri tree is the active development target; the Swift app is in
maintenance mode. Issue [#25](https://github.com/lpalokan/bmad-manager/issues/25)
tracks the full Windows shipping plan.

**Stage 3** is now landed: the NSIS installer bundles portable Node
and PortableGit alongside a pre-warmed `bmad-method` npm cache, so
end users double-click one `.exe` and have a working app with zero
prerequisite installs. The installer is per-user (no UAC prompt) and
the `.github/workflows/tauri-windows.yml` release pipeline produces it
on every push to the Stage 3 branch (and attaches it to a GitHub
Release on `windows-v*` tag pushes).

## Layout

```
tauri/
  package.json, vite.config.ts, svelte.config.js, tsconfig.json
  index.html
  cucumber.json                       cucumber-js config — JSON not JS
                                      (see "Why cucumber.json" below)
  src/                                Svelte frontend
    App.svelte                        top-level shell + state
    main.ts, app.css
    lib/
      commands.ts                     invoke() wrappers per Tauri command
      types.ts                        shared types mirroring Rust models
      Settings.svelte                 modal: projects root, module source,
                                      init command, terminal, commands
      ProjectRow.svelte               one row per project
      CommandOutput.svelte            streaming stdout/stderr panel
  src-tauri/                          Rust + Tauri 2
    Cargo.toml, build.rs, tauri.conf.json
    capabilities/default.json         IPC permission set
    src/
      main.rs                         thin entry point
      lib.rs                          tauri::Builder + commands + state
      commands.rs                     Tauri command handlers
      models/
        settings.rs                   AppSettings + enums; legacy decoder
        project_item.rs               ProjectItem
      services/
        settings_store.rs             load/save settings.json
        project_service.rs            validate, create, list, trash
        zip_source.rs                 .zip extract + wrapper-folder
        git_source.rs                 git clone --depth 1
        command_runner.rs             stream stdout/stderr via events
        project_creator.rs            full create pipeline
        init_command.rs               placeholder sub + shell quoting
      platform/                       OS abstraction (issue #25)
        mod.rs                        cfg-based re-exports + AppHandle slot
        windows.rs                    Stage 2 implementations
        macos.rs                      future macOS unification milestone
        stub.rs                       Linux/CI fallback for unit + BDD
    tests/
      bdd.rs                          custom cucumber-rs harness
      features/                       Gherkin scenarios per concern
      steps/, support/                step bindings + shared World
    icons/                            generated from ../Resources/icon-source.png
  tests/                              Svelte UI BDD (cucumber-js, TypeScript)
    features/smoke.feature            Stage 1 smoke; Stage 3 adds Playwright
    steps/, support/
```

## Prerequisites

- **Rust** stable (`rustup install stable`)
- **Node.js** 22 LTS
- **pnpm** — pinned via `packageManager` in `package.json`; enable
  [corepack](https://nodejs.org/api/corepack.html) (`corepack enable`)
  and pnpm tracks the pinned version automatically.
- **Windows targets only need MSVC + WebView2** — the GitHub Actions runner has both. For a local Windows dev loop see [the Tauri Windows prerequisites](https://v2.tauri.app/start/prerequisites/#windows).
- **macOS dev loop** also works (`pnpm tauri dev`) for the frontend; calls into `platform::macos` panic with `unimplemented!()` until the unification milestone.

## Install + run

```
pnpm install
pnpm tauri dev
```

The window opens with the three Stage 1 regions: header (with output toggle and settings cogwheel), project list area (placeholder), and a hidden output panel that the toggle reveals.

To produce a release bundle (Windows machines only — produces an NSIS installer at `src-tauri/target/release/bundle/nsis/`):

```
pnpm tauri build
```

## Tests

Svelte UI BDD (cucumber-js + tsx):

```
pnpm test:bdd
```

Rust BDD (cucumber-rs harness):

```
cargo test --manifest-path src-tauri/Cargo.toml --test bdd
```

Rust unit tests (every `#[cfg(test)] mod tests` block under `src-tauri/src/`):

```
cargo test --manifest-path src-tauri/Cargo.toml --lib
```

See [`../CLAUDE.md`](../CLAUDE.md) for the BDD-first policy.

### Why `cucumber.json` and not `cucumber.ts`/`cucumber.js`

cucumber-js 11 loads an ESM `cucumber.js` config silently as `undefined` on Node 22 if the file uses a default export — debugging the misload eats hours. JSON sidesteps the loader entirely. If a future cucumber-js release fixes this, feel free to move back to a `.ts` config; until then, keep this file.

The TS step bindings run via `node --import tsx` (see the `test:bdd` script in `package.json`) because `tsx` removed the deprecated `--loader` hook that cucumber-js's `loader` config field used to drive.

## Type check + lint

Svelte type-check:

```
pnpm check
```

Rust crate check:

```
cargo check --manifest-path src-tauri/Cargo.toml
```

## CI

`tauri-windows-check.yml` exercises `cargo fmt`, `cargo clippy
--all-targets -D warnings`, `cargo check`, `cargo test --lib`, `cargo
test --test bdd`, `pnpm build`, `pnpm check`, and `pnpm test:bdd` on
`windows-latest` for every push to `main` and the active feature
branch — the fast feedback loop while iterating.

`tauri-windows.yml` is the release pipeline. It downloads the pinned
portable Node (`NODE_VERSION` env var) and PortableGit
(`GIT_FOR_WINDOWS_VERSION` + `GIT_FOR_WINDOWS_TAG`), pre-warms the npm
cache with `bmad-method`, runs `pnpm tauri build`, and uploads the
resulting NSIS installer as a workflow artifact named
`BmadManager-windows-x64-<sha>.exe`. Tagging the commit with
`windows-v*` additionally publishes a GitHub Release with the
installer attached.

The bundled binaries live under `src-tauri/resources/`:

```
src-tauri/resources/
  node-portable/        bundled Node 22.x  (CI-populated, .gitignored)
  portable-git/         bundled Git 2.47.x (CI-populated, .gitignored)
  npm-cache/            pre-warmed bmad-method cache (CI-populated)
```

At first launch the app copies `npm-cache/` into the user-writable
`%LOCALAPPDATA%\bmad-manager\npm-cache` and points `NPM_CONFIG_CACHE`
at it; subsequent runs reuse the user cache.

The Rust unit tests and BDD scenarios run on Linux too (the
`platform::stub` arm returns dev-friendly defaults), so the dev loop
on a non-Windows machine can run everything except the actual
`wt.exe` / `cmd /K` calls and the NSIS bundle.
