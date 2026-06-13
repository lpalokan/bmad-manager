Feature: Global skills repository sync
  The pure helpers behind the "Sync to Claude Code / Codex" buttons —
  managed-folder resolution, token-safe auth header, and settings persistence.

  Scenario: managed dir for Claude Code lives under .claude
    When I compute the managed skills dir for "claude" under home "/home/me"
    Then the managed skills dir is "/home/me/.claude/skills/managed"

  Scenario: managed dir for Codex lives under .codex
    When I compute the managed skills dir for "codex" under home "/home/me"
    Then the managed skills dir is "/home/me/.codex/skills/managed"

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
