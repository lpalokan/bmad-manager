# Active platform

This repository ships two coexisting trees:

- **Swift macOS app** (`Sources/BmadManager/`, built by `scripts/build_release.sh` into `bmad-manager.app`) — **the actively shipped platform**. New features land here so they reach users on Mac on the next release build.
- **Tauri Windows port** (`tauri/`) — work-in-progress cross-platform rewrite. Its macOS arm (`tauri/src-tauri/src/platform/macos.rs`) is intentionally `unimplemented!()` until the unification milestone, so it cannot ship on Mac today. Mirror Swift features into the Tauri tree only when both platforms are explicitly in scope, or when the request names Windows specifically.

When a request is ambiguous about which tree, default to Swift and confirm.

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

Apply the prefix to **both** the PR title and at least one commit on the feature branch. release-please reads whichever ends up on `main`: merge-commit and rebase merges preserve the individual feature-branch commits, while squash merges collapse everything into a single commit whose default message is the PR title. Prefixing both keeps releases triggering regardless of which merge style is used on a given PR.

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

The Swift macOS app under `Sources/BmadManager/` is the active platform (see "Active platform" above). New behaviour lands in the Swift tree first with full Gherkin coverage. The Tauri Windows port (`tauri/`) gets the equivalent scenarios when a request explicitly covers Windows or both platforms.

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

**Swift macOS app** (`Sources/BmadManager/`, the active platform — features land here first):

- Tests live alongside their unit under `Tests/BmadManagerTests/<ThingTests>.swift` (XCTest). A Gherkin layer was scoped but never wired into `Package.swift`; the test-first discipline is still mandatory — write the failing `XCTestCase` first, watch it fail for the right reason, then implement. Use scenario-style test names (`testDecodesLegacySettingsWithoutPiCommand`) so the intent reads like a spec.
- Run:

  ```
  swift test
  ```

See `docs/testing.md` for the full workflow, step catalogue, and maintenance guide.
