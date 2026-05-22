# BMad Manager — Tauri (Windows-first)

Cross-platform port of the Swift macOS app under [`Sources/BmadManager/`](../Sources/BmadManager).
The Tauri tree is the active development target; the Swift app is in
maintenance mode. Issue [#25](https://github.com/lpalokan/bmad-manager/issues/25)
tracks the full Windows shipping plan.

This directory holds **Stage 1** of that plan: the Tauri + Svelte
scaffold, platform module skeleton, and BDD test harnesses. No business
logic yet — Stage 2 ports the Swift services, Stage 3 bundles Node + Git
and wires the GitHub Release workflow.

## Layout

```
tauri/
  package.json, vite.config.ts, svelte.config.js, tsconfig.json
  index.html
  cucumber.json                       cucumber-js config (Stage 1 smoke)
  src/                                Svelte frontend
    App.svelte                        three-region UI shell
    main.ts, app.css
  src-tauri/                          Rust + Tauri 2
    Cargo.toml, build.rs, tauri.conf.json
    src/
      main.rs                         thin entry point
      lib.rs                          tauri::Builder wiring
      platform/                       OS abstraction (issue #25)
        mod.rs                        cfg-based re-exports + TerminalKind
        windows.rs                    Stage 2 fills these in
        macos.rs                      future macOS unification milestone
        stub.rs                       Linux/CI fallback (unimplemented!())
    tests/
      bdd.rs                          custom cucumber-rs harness
      features/smoke.feature
      steps/, support/
    icons/                            generated from ../Resources/icon-source.png
  tests/                              Svelte UI BDD (cucumber-js + Playwright in Stage 2)
    features/smoke.feature
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
pnpm test:bdd                                              Svelte UI BDD smoke
cargo test --manifest-path src-tauri/Cargo.toml --test bdd  Rust BDD smoke
```

Both currently run a single placeholder scenario that verifies the harness wires up. Stage 2 grows the catalogue alongside the service ports. See [`../CLAUDE.md`](../CLAUDE.md) for the BDD-first policy.

## Type check + lint

```
pnpm check                                          svelte-check
cargo check --manifest-path src-tauri/Cargo.toml    Rust crate
```

## What's *not* here yet

| Stage | Scope |
|-------|-------|
| 2 | Rust services port, Tauri commands, real Svelte UI, settings persistence, project lifecycle |
| 3 | Bundled portable Node + PortableGit, pre-warmed `bmad-method` npm cache, `tauri-windows.yml` release workflow |

A minimal `tauri-windows-check.yml` workflow exercises `cargo check`, `pnpm build`, and both BDD smokes on `windows-latest` for every push to the Stage 1 branch.
