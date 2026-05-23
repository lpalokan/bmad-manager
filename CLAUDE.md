# GitHub Workflow

Never merge pull requests. Only create PRs. The user will review, merge, and close them.

Never add commits to a branch after its PR has been merged. Once merged, create a new branch from `main` for any remaining work.

Create a separate feature branch per task from the task breakdown in GitHub Issues.

Branch naming: `feature/N-short-description` (where `N` is the GitHub issue number).

Push the branch and create a PR targeting `main`.

Reference the issue number in the PR body (e.g., "Closes #2").

When working on a feature branch, always `git add -A && git commit` and `git push origin <branch>` before declaring the work done. Uncommitted or unpushed changes are incomplete.

# Commit message conventions

[release-please](https://github.com/googleapis/release-please) drives versioning from conventional-commit prefixes on `main`. Without these prefixes the bot will never open a Release PR and the publish pipeline stays idle.

- `feat: ...` — minor bump
- `fix: ...` — patch bump
- `feat!: ...` or trailer `BREAKING CHANGE: ...` — major bump (pre-1.0, configured as minor)
- `chore:`, `docs:`, `refactor:`, `test:`, `ci:`, `build:` — no bump, no CHANGELOG entry

Commits without a recognised prefix are silently ignored by the bot, so a stray `Fix typo` commit will not trigger a release.

# Shell command conventions

When giving the user shell commands to run, do not put inline `#` comments in the command blocks (neither trailing nor standalone). The user pastes blocks into zsh and the comments cause confusion. Put any explanation in prose before or after the block instead.

# BDD-first development (mandatory)

Every new feature or behaviour change MUST start with Gherkin scenarios, before any implementation code:

1. **Write/extend the `.feature` file first.** Add scenarios in plain English under the project's `features/` directory (see paths per stack below). This is the source of truth for what the feature does.
2. **Wire steps to the harness.** Reuse existing steps where possible; only add a new step definition when no existing phrase fits. Step files delegate to a thin support harness that owns app setup, teardown, and shared fixtures — never inline app wiring into a step.
3. **Generate and run the failing test** and confirm it fails for the right reason (red).
4. **Only then implement the feature** until the scenario passes (green), then refactor.

Do not write feature/implementation code before its Gherkin scenario exists and fails. Bug fixes follow the same loop: add a scenario that reproduces the bug first.

## Per-stack BDD layout and commands

The Swift macOS app under `Sources/BmadManager/` is in maintenance mode while the Tauri Windows port is the active development target. New behaviour lands in the Tauri tree; the Swift tree gets BDD coverage only when a bug fix or back-port requires it.

**Tauri Rust backend** (`tauri/src-tauri/`):

- Features: `tauri/src-tauri/tests/features/*.feature`
- Step definitions: `tauri/src-tauri/tests/steps/` (cucumber-rs)
- Support harness: `tauri/src-tauri/tests/support/`
- Run:

  ```
  cargo test --manifest-path tauri/src-tauri/Cargo.toml --test bdd
  ```

**Svelte UI end-to-end** (`tauri/`):

- Features: `tauri/tests/features/*.feature`
- Step definitions: `tauri/tests/steps/` (`@cucumber/cucumber` driving Playwright against `pnpm tauri dev`)
- Support harness: `tauri/tests/support/`
- Run:

  ```
  pnpm --dir tauri test:bdd
  ```

**Swift macOS app** (`Sources/BmadManager/`, only when a bug fix needs a regression scenario):

- Features: `Tests/BmadManagerTests/Features/*.feature`
- Step bindings: `Tests/BmadManagerTests/Features/Steps/` (XCTest-backed)
- Run:

  ```
  swift test --filter BmadManagerTests.Features
  ```

See `docs/testing.md` for the full workflow, step catalogue, and maintenance guide.
