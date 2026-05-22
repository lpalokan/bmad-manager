use cucumber::{given, then};

use crate::support::TauriWorld;

#[given("the Tauri Rust crate has been scaffolded")]
async fn rust_crate_scaffolded(_world: &mut TauriWorld) {
    // Stage 1 marker step — the fact that this binary linked means the
    // crate compiled. Stage 2 replaces this with real preconditions.
}

#[then("the BDD harness runs")]
async fn harness_runs(_world: &mut TauriWorld) {
    // Reaching this step proves cucumber discovered the feature file,
    // matched the step bindings, and executed them.
}
