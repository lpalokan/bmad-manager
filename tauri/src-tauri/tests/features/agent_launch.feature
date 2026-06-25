Feature: Agent launch method resolution

  bmad-manager lets a user pick how a coding agent that ships both a CLI and
  a desktop app (Claude, Codex) is launched: Auto (prefer the app when it is
  installed, otherwise run the CLI in the terminal), App (always the GUI), or
  CLI (always the terminal). This is the pure preference -> concrete-decision
  policy, mirroring the macOS AgentLaunchResolver, so a Windows user who only
  has the Codex GUI installed gets the GUI by default.

  Scenario: auto prefers the app when it is installed
    Given the launch method "auto"
    And the agent app is installed
    When I resolve the launch
    Then the resolved launch is "app"

  Scenario: auto falls back to the CLI when the app is not installed
    Given the launch method "auto"
    And the agent app is not installed
    When I resolve the launch
    Then the resolved launch is "cli"

  Scenario: an explicit app choice is honoured even when the app is not detected
    Given the launch method "app"
    And the agent app is not installed
    When I resolve the launch
    Then the resolved launch is "app"

  Scenario: cli always resolves to the CLI even when the app is installed
    Given the launch method "cli"
    And the agent app is installed
    When I resolve the launch
    Then the resolved launch is "cli"
