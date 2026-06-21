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

  Scenario: updating preserves user data under _bmad-output
    Given an existing project "proj" to update
    And the project has a user file "_bmad-output/work/notes.md" with content "keep me"
    And update settings whose init command succeeds
    When I update the project
    Then the update succeeds
    And the project file "_bmad-output/work/notes.md" still has content "keep me"

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
