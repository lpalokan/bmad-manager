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

  Scenario: a project with an unreadable installed version is not flagged
    Given a project "broken" with installed module version "garbage"
    When I check it against repo module version "2.1.0"
    Then the project reports no update available

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
