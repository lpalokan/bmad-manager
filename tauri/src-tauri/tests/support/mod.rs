//! Shared cucumber `World` and test fixtures. Stage 1 keeps this empty
//! beyond the marker struct; Stage 2 adds an in-memory settings store,
//! a fake `CommandRunner`, and helpers for materialising temp project
//! folders so step files stay thin.

use cucumber::World;

#[derive(Debug, Default, World)]
pub struct TauriWorld;
