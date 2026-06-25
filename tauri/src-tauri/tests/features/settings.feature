Feature: AppSettings serialization and defaults

  The settings model is the source of truth for everything the user can
  configure (projects root, module source, init command, terminal). It
  must round-trip through JSON cleanly and tolerate legacy files written
  by older versions of the macOS Swift app, so a user porting their
  settings.json to Windows keeps the workflow they already had.

  Scenario: defaults are sensible
    When I read the default settings
    Then the projects root is non-empty and absolute
    And the init command contains "{PROJECT_PATH}"
    And the init command contains "{MODULE_SOURCE}"
    And the module source kind is "gitRepo"
    And the project sort order is "nameAscending"
    And the claude command is "claude"
    And the opencode command is "opencode"
    And the pi command is "pi"
    And the codex command is "codex"
    And the init command contains "codex"

  Scenario: defaults round-trip through JSON
    When I encode the default settings and decode them again
    Then the decoded settings equal the originals

  Scenario: legacy settings without sort order default to name ascending
    Given a legacy settings JSON without projectSortOrder
    When I decode it
    Then the project sort order is "nameAscending"

  Scenario: legacy settings with configured zip path infer local zip source
    Given a legacy settings JSON without moduleSourceKind but with a non-empty moduleZipPath
    When I decode it
    Then the module source kind is "localZip"

  Scenario: legacy settings without zip path default to git repo source
    Given a legacy settings JSON without moduleSourceKind and with an empty moduleZipPath
    When I decode it
    Then the module source kind is "gitRepo"

  Scenario: legacy settings without terminal kind default per platform
    Given a legacy settings JSON without terminalKind
    When I decode it
    Then the terminal kind matches the platform default

  Scenario: legacy settings without pi command default to "pi"
    Given a legacy settings JSON without piCommand
    When I decode it
    Then the pi command is "pi"

  Scenario: round-trip preserves a customised pi command
    When I round-trip the default settings with pi command "C:\\bin\\pi.exe"
    Then the decoded pi command is "C:\\bin\\pi.exe"

  Scenario: legacy settings without codex command default to "codex"
    Given a legacy settings JSON without codexCommand
    When I decode it
    Then the codex command is "codex"

  Scenario: round-trip preserves a customised codex command
    When I round-trip the default settings with codex command "C:\\bin\\codex.exe"
    Then the decoded codex command is "C:\\bin\\codex.exe"

  Scenario: defaults prefer auto launch for claude and codex
    When I read the default settings
    Then the codex launch method is "auto"
    And the claude launch method is "auto"

  Scenario: legacy settings without codex launch method default to auto
    Given a legacy settings JSON without codexLaunchMethod
    When I decode it
    Then the codex launch method is "auto"

  Scenario: round-trip preserves a chosen codex launch method
    When I round-trip the default settings with codex launch method "app"
    Then the decoded codex launch method is "app"

  Scenario: legacy settings without claude launch method default to auto
    Given a legacy settings JSON without claudeLaunchMethod
    When I decode it
    Then the claude launch method is "auto"

  Scenario: round-trip preserves a chosen claude launch method
    When I round-trip the default settings with claude launch method "cli"
    Then the decoded claude launch method is "cli"

  Scenario: launch method serializes to a portable camelCase key
    When I round-trip the default settings with codex launch method "app"
    Then the encoded settings JSON has "codexLaunchMethod" set to "app"

  Scenario: legacy settings without shell kind default to Command Prompt
    Given a legacy settings JSON without shellKind
    When I decode it
    Then the shell kind is "cmd"

  Scenario: round-trip preserves a chosen shell kind
    When I round-trip the default settings with shell kind "powershell"
    Then the decoded shell kind is "powershell"

  Scenario: legacy settings without new-session placement default to new window
    Given a legacy settings JSON without newSessionPlacement
    When I decode it
    Then the new session placement is "newWindow"

  Scenario: round-trip preserves a chosen new-session placement
    When I round-trip the default settings with new session placement "newTab"
    Then the decoded new session placement is "newTab"
