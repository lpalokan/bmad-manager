Feature: Global skills repository sync
  Pure helpers behind the "Sync to Claude Code / Codex" buttons: where the repo
  is cloned, where skills are linked, token-safe auth, and settings persistence.

  Scenario: Claude Code skills live under .claude/skills
    When I compute the skills root for "claude" under home "/home/me"
    Then the skills path is "/home/me/.claude/skills"

  Scenario: the cloned repo lives in a hidden sibling, not under skills
    When I compute the managed repo dir for "codex" under home "/home/me"
    Then the skills path is "/home/me/.codex/skills-managed"

  Scenario: the auth header carries the token without leaking it
    When I build the skills auth header for token "ghp_supersecret"
    Then the skills auth header starts with "AUTHORIZATION: basic "
    And the skills auth header does not contain "ghp_supersecret"

  Scenario: skills settings round-trip through JSON
    Given skills settings with repo "https://github.com/acme/skills" and branch "release"
    When I encode and decode the skills settings
    Then the decoded skills repo URL is "https://github.com/acme/skills"
    And the decoded skills repo branch is "release"

  Scenario: legacy settings without skills fields default the branch to main
    Given a legacy settings JSON without skills fields
    When I decode the legacy settings
    Then the decoded skills repo URL is ""
    And the decoded skills repo branch is "main"
