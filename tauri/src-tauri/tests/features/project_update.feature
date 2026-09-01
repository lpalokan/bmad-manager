Feature: Update existing projects from the bmad-repo

  Detect which already-created projects are behind the configured module
  repo's latest version, and re-install the latest over an existing project,
  refreshing the managed AGENTS.md blocks without touching user data.

  # --- Version check (which projects are behind) ---

  Scenario: a project behind the latest module version is flagged
    Given a project "stale" with installed module version "2.0.0"
    When I check it against repo module version "2.1.0"
    Then the project reports an update is available

  Scenario: a project at the latest module version is not flagged
    Given a project "current" with installed module version "2.1.0"
    When I check it against repo module version "2.1.0"
    Then the project reports no update available

  Scenario: a project without the marketing-growth module is not flagged
    Given a project "other" with no marketing-growth module
    When I check it against repo module version "2.1.0"
    Then the project reports no update available

  Scenario: a project pinned to a branch ref is flagged for reinstall
    Given a project "branch-pinned" with installed module version "main"
    When I check it against repo module version "2.1.0"
    Then the project reports an update is available

  Scenario: a project is not flagged when the repo version is also non-comparable
    Given a project "branch-pinned" with installed module version "main"
    When I check it against repo module version "main"
    Then the project reports no update available

  # --- Version check end-to-end (reads the latest version from the module
  #     source, the path `check_for_updates` runs and the one a behind
  #     project travels before its Update button appears) ---

  Scenario: the version check reads the module source and flags a behind project
    Given a project "behind" with installed module version "2.0.0"
    And a marketing-growth module source at version "2.0.2"
    When I run the version check
    Then the version check reports "behind" needs an update

  Scenario: the version check flags a branch-pinned project against a real semver source
    Given a project "pinned" with installed module version "main"
    And a marketing-growth module source at version "2.0.2"
    When I run the version check
    Then the version check reports "pinned" needs an update

  Scenario: the version check clears a project already at the latest version
    Given a project "current" with installed module version "2.0.2"
    And a marketing-growth module source at version "2.0.2"
    When I run the version check
    Then the version check reports no projects need an update

  # --- Version check end-to-end against a GIT source (the default on Windows:
  #     a clone whose module sits at the repo root, not a zip wrapper). This is
  #     the path the reported missing-Update-button bug actually travels. ---

  Scenario: the version check reads a git source and flags a behind project
    Given a project "git-behind" with installed module version "2.0.0"
    And a marketing-growth git source at version "2.0.2"
    When I run the version check
    Then the version check reports "git-behind" needs an update

  Scenario: the version check clears a current project against a git source
    Given a project "git-current" with installed module version "2.0.2"
    And a marketing-growth git source at version "2.0.2"
    When I run the version check
    Then the version check reports no projects need an update

  # --- Per-project update (re-install + AGENTS.md refresh) ---

  Scenario: updating re-installs and refreshes the bmad AGENTS.md block
    Given an existing project "proj" to update
    And update settings whose init command succeeds
    When I update the project
    Then the update succeeds
    And the project AGENTS.md contains the bmad block

  Scenario: updating injects the okf block when the module ships the template
    Given an existing project "proj" to update
    And update settings whose init command succeeds, with okf template "Use the company-context OKF bundle."
    When I update the project
    Then the update succeeds
    And the project AGENTS.md contains the okf block "Use the company-context OKF bundle."

  Scenario: updating skips the okf block when the template is absent
    Given an existing project "proj" to update
    And update settings whose init command succeeds
    When I update the project
    Then the update succeeds
    And the project AGENTS.md has no okf block

  Scenario: updating preserves user data under output
    Given an existing project "proj" to update
    And the project has a user file "output/work/notes.md" with content "keep me"
    And update settings whose init command succeeds
    When I update the project
    Then the update succeeds
    And the project file "output/work/notes.md" still has content "keep me"

  Scenario: updating preserves user data under the legacy _bmad-output
    Given an existing project "proj" to update
    And the project has a user file "_bmad-output/work/notes.md" with content "keep me"
    And update settings whose init command succeeds
    When I update the project
    Then the update succeeds
    And the project file "_bmad-output/work/notes.md" still has content "keep me"

  # The create path appends `--output-folder output` (issue #99); the update
  # path must not. The installer lets a CLI flag override a project's
  # remembered answer, so an existing project would silently flip
  # `[core] output_folder` to a folder its files are not in.
  Scenario: updating does not pass the create-path output folder flag
    Given an existing project "proj" to update
    And update settings whose init command records its arguments
    When I update the project
    Then the update succeeds
    And the project file "init-args.txt" does not contain "--output-folder"

  Scenario: a failing update surfaces an error and leaves the project inspectable
    Given an existing project "proj" to update
    And update settings whose init command fails
    When I update the project
    Then the update fails
    And the project folder still exists

  # --- Git source: the repo URL (with resolved tag) reaches --custom-source ---

  Scenario: a git-source update passes the repo URL and latest tag to custom-source
    Given an existing project "git-proj" to update
    And git update settings with a module repo tagged "v2.0.2"
    When I update the project
    Then the update succeeds
    And the project file "module-source.txt" contains "@v2.0.2"
    And the project file "module-source.txt" contains "file://"

  # --- The single Update button also covers context drift (issue #92) ---
  #
  # The same per-project Update button lights up (and its action syncs) for
  # a project that is current on its module but behind on the skills-repo
  # company-context — the user never needs to know which one changed.

  Scenario: a project current on its module but behind on context still needs an update
    Given a project "current-module" with installed module version "2.1.0"
    And a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And project "current-module" seeded from the "digital-workforce" skills repo context
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-07-03"
    When I run the combined update check against repo module version "2.1.0"
    Then the project reports an update is available

  Scenario: a project current on both its module and its context needs no update
    Given a project "all-current" with installed module version "2.1.0"
    And a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And project "all-current" seeded from the "digital-workforce" skills repo context
    When I run the combined update check against repo module version "2.1.0"
    Then the project reports no update available

  # --- The check's own diagnostic line (issue #105) ---
  #
  # The line streamed per project is the only window the user has into why a
  # project did or didn't get an Update button. It has to name the context
  # state it actually reached, or an unresolvable upstream reads as "current"
  # and the wrong answer stays invisible.

  Scenario: the check line reports drift on the context axis
    Given a project "drifted" with installed module version "2.1.0"
    And a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And project "drifted" seeded from the "digital-workforce" skills repo context
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-07-03"
    When I run the combined update check against repo module version "2.1.0"
    Then the update check line contains "context=drift"
    And the update check line contains "-> UPDATE"

  Scenario: the check line reports an unresolvable upstream as no-upstream
    Given a project "split" with installed module version "2.1.0"
    And a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a skills repo context "healthcare" with OKF file "positioning.md" dated "2026-06-26"
    And project "split" seeded from the "digital-workforce" skills repo context under "output/company-context"
    And project "split" has a local context file "vertical.md" tagged "healthcare"
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-07-03"
    When I run the combined update check against repo module version "2.1.0"
    Then the update check line contains "context=no-upstream"
    And the project reports no update available

  Scenario: the check line reports a project with no context at all
    Given a project "module-only" with installed module version "2.1.0"
    And a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    When I run the combined update check against repo module version "2.1.0"
    Then the update check line contains "context=no-context"

  Scenario: updating also refreshes drifted company-context from the skills repo
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And an existing project "proj" to update
    And project "proj" seeded from the "digital-workforce" skills repo context
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-07-03"
    And update settings whose init command succeeds
    When I update the project
    Then the update succeeds
    And project "proj" context file "positioning.md" is dated "2026-07-03"

  # --- What the installer is told to install (issue: the Update button that
  #     never clears) ---
  #
  # `bmad-method` records whatever ref it was given as the module version. A
  # bare URL or a branch ref makes it stamp `main`, which `is_project_stale`
  # can never compare against a real semver — so the project is flagged
  # forever and re-running Update rewrites the same `main`. Resolution must
  # say, in the output panel, when the install will not record a version.

  Scenario: an unset ref pins the repo's latest version tag
    When I describe the installer source for "https://github.com/acme/mod" with ref "" and tags "v1.0.0, v2.5.0"
    Then the installer source argument is "https://github.com/acme/mod@v2.5.0"
    And the installer source records a version
    And the installer source note contains "latest tag v2.5.0"

  Scenario: an explicit version tag is pinned as configured
    When I describe the installer source for "https://github.com/acme/mod" with ref "v2.4.0" and tags "v2.5.0"
    Then the installer source argument is "https://github.com/acme/mod@v2.4.0"
    And the installer source records a version
    And the installer source note contains "from Settings"

  Scenario: a branch ref warns that the install will record no version
    When I describe the installer source for "https://github.com/acme/mod" with ref "main" and tags "v2.5.0"
    Then the installer source argument is "https://github.com/acme/mod@main"
    And the installer source does not record a version
    And the installer source note contains "not a version tag"
    And the installer source note contains "keep showing an update"

  Scenario: an unreadable tag list warns instead of silently installing the default branch
    When I describe the installer source for "https://github.com/acme/mod" with ref "" and no tag listing
    Then the installer source argument is "https://github.com/acme/mod"
    And the installer source does not record a version
    And the installer source note contains "could not list the version tags"
    And the installer source note contains "keep showing an update"

  Scenario: a repo without version tags warns as well
    When I describe the installer source for "https://github.com/acme/mod" with ref "" and tags "latest, nightly"
    Then the installer source argument is "https://github.com/acme/mod"
    And the installer source does not record a version
    And the installer source note contains "no version tags"

  # The version check must read the module version from the same ref the
  # install pins, or a repo whose default branch runs ahead of its newest tag
  # flags every project forever.
  Scenario: the version check reads the version from the tag that would be installed
    Given a project "tagged" with installed module version "2.0.2"
    And a marketing-growth git source tagged "v2.0.2" whose default branch is version "3.0.0"
    When I run the version check
    Then the version check reports no projects need an update

  # The line is the only place the user can see why the button stays lit.
  Scenario: the check line explains an installed version that is not a version number
    Given a project "branchy" with installed module version "main"
    When I run the combined update check against repo module version "2.5.0"
    Then the project reports an update is available
    And the update check line contains "installed version is not a version number"
