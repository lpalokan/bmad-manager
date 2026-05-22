# BMad Manager — Tauri (Windows-first)

Cross-platform port of the Swift macOS app under [`Sources/BmadManager/`](../Sources/BmadManager).
The Tauri tree is the active development target; the Swift app is in
maintenance mode. Issue [#25](https://github.com/lpalokan/bmad-manager/issues/25)
tracks the full Windows shipping plan.

**Stage 2** is now landed: Rust ports of every Swift service
(`SettingsStore`, `ProjectService`, both `ModuleSource` adapters,
`CommandRunner`, `ProjectCreator`), the full `platform::windows` arm,
seven Tauri commands wiring them to the frontend, and four Svelte
components (`Settings`, `ProjectRow`, `CommandOutput`, and the main
`App`). Stage 3 still has to bundle Node + Git and ship a GitHub Release.

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
- **pnpm** 10.x
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

```
pnpm test:bdd                                              Svelte UI BDD
cargo test --manifest-path src-tauri/Cargo.toml --test bdd  Rust BDD
cargo test --manifest-path src-tauri/Cargo.toml             Rust unit tests
```

See [`../CLAUDE.md`](../CLAUDE.md) for the BDD-first policy.

### Why `cucumber.json` and not `cucumber.ts`/`cucumber.js`

cucumber-js 11 loads an ESM `cucumber.js` config silently as `undefined` on Node 22 if the file uses a default export — debugging the misload eats hours. JSON sidesteps the loader entirely. If a future cucumber-js release fixes this, feel free to move back to a `.ts` config; until then, keep this file.

The TS step bindings run via `node --import tsx` (see the `test:bdd` script in `package.json`) because `tsx` removed the deprecated `--loader` hook that cucumber-js's `loader` config field used to drive.

## Type check + lint

```
pnpm check                                          svelte-check
cargo check --manifest-path src-tauri/Cargo.toml    Rust crate
```

## What's *not* here yet

| Stage | Scope |
|-------|-------|
| 3 | Bundled portable Node + PortableGit under `src-tauri/resources/`, pre-warmed `bmad-method` npm cache, `tauri-windows.yml` release workflow producing a downloadable `.exe`, README install instructions for end users |

`tauri-windows-check.yml` exercises `cargo fmt`, `cargo clippy --all-targets -D warnings`, `cargo check`, `cargo test --lib`, `cargo test --test bdd`, `pnpm build`, `pnpm check`, and `pnpm test:bdd` on `windows-latest` for every push to `main` and the Stage 2 branch.

The Rust unit tests and BDD scenarios run on Linux too (the `platform::stub` arm returns dev-friendly defaults), so the dev loop on a non-Windows machine can run everything except the actual `wt.exe` / `cmd /K` calls.
