Feature: Stage 1 scaffold smoke

  Verifies the cucumber-rs harness wired up in `tests/bdd.rs` discovers
  features, matches step bindings, and runs to completion. Subsequent
  stages add real behavioural scenarios alongside this smoke.

  Scenario: BDD harness runs
    Given the Tauri Rust crate has been scaffolded
    Then the BDD harness runs
