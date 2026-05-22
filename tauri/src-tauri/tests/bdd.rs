//! Custom cucumber-rs test binary. Discovers `.feature` files under
//! `tests/features/` and runs the step bindings declared in `tests/steps/`.
//!
//! Per `CLAUDE.md` BDD-first policy: every new Tauri Rust behaviour must
//! land here as a Gherkin scenario before its implementation. Stage 1 ships
//! a single smoke scenario; Stage 2 expands the catalogue alongside the
//! ports of the Swift services.

mod steps;
mod support;

use support::TauriWorld;

#[tokio::main]
async fn main() {
    TauriWorld::run("tests/features").await;
}
