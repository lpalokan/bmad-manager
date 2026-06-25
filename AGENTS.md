# Active platform

This repository ships two coexisting trees:

- **Swift macOS app** (`Sources/BmadManager/`, built by `scripts/build_release.sh` into `bmad-manager.app`) — **the actively shipped platform**. New features land here so they reach users on Mac on the next release build.
- **Tauri Windows port** (`tauri/`) — cross-platform rewrite covering Windows. Its macOS arm (`tauri/src-tauri/src/platform/macos.rs`) is intentionally `unimplemented!()` until the unification milestone, so it cannot ship on Mac today.

**Features are per-platform — don't port across by default.** Mac users run the Swift app; Windows users run the Tauri port. A change lands in the tree whose platform's users it's for, and only touches both trees when the request explicitly spans both platforms (or names the other one). Say which tree(s) you changed and why.

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

The Swift macOS app under `Sources/BmadManager/` serves Mac users and the Tauri Windows port (`tauri/`) serves Windows users (see "Active platform" above). Write Gherkin coverage in the tree whose platform the change targets; only cover both when the request explicitly spans both platforms.

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

# Codebase knowledge graph (graphify)

A queryable knowledge graph of this repo lives under `graphify-out/` (git-ignored). A `post-commit` hook auto-refreshes it after every commit — **code/AST only, in the background, no LLM** — so the structural graph stays current with no manual step.

**Use it for comprehension, not editing.** Before grepping to understand how something works ("how does X work", "what calls Y", "trace the flow through Z"), query the graph first — it returns the relevant nodes and edges with `file:line` citations, faster than reconstructing structure by hand:

```
graphify query "how does the project-create flow work"
```

In Claude Code the `/graphify` skill wraps the same query. For making edits, still read the files directly: the graph is a map, not the source of truth, and brand-new code can lag until the background rebuild finishes.

**Refreshing semantic content.** The commit hook re-extracts only code structure. Cross-file, doc, and image *semantic* edges refresh on a full `/graphify` run (LLM-backed) — run one after large doc or cross-cutting changes if you want the graph's prose understanding current.
