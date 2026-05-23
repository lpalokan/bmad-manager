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
    And the init command contains "{MODULE_PATH}"
    And the module source kind is "gitRepo"
    And the project sort order is "nameAscending"
    And the claude command is "claude"
    And the opencode command is "opencode"
    And the pi command is "pi"

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
