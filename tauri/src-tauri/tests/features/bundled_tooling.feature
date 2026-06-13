Feature: Bundled tooling discovery and npm cache seeding

  Stage 3 of issue #25 ships portable Node and PortableGit inside the
  NSIS installer so end users don't need to install either. The app
  needs to (1) report the bundled tool versions in the Settings dialog
  so a confused user can answer "what version of Node is this running?"
  without digging into AppData, and (2) seed the user-writable npm
  cache directory from the pre-warmed cache baked into the installer
  the first time the app launches — so the first project creation
  succeeds even on a flaky network.

  Scenario: version detection returns None when the binary is missing
    Given a path that points at no file
    When I detect the version with "--version"
    Then the detected version is unavailable

  Scenario: version detection extracts the first line of stdout
    Given a stub binary that prints "v22.11.0" then "extra noise"
    When I detect the version with "--version"
    Then the detected version is "v22.11.0"

  Scenario: seed the user npm cache from the bundled cache on first launch
    Given a bundled npm cache containing a marker package
    And no user npm cache directory exists yet
    When I seed the user npm cache from the bundled cache
    Then the seed reports it copied the cache
    And the user npm cache contains the marker package

  Scenario: do not overwrite an existing user npm cache
    Given a bundled npm cache containing a marker package
    And the user npm cache already contains a different package
    When I seed the user npm cache from the bundled cache
    Then the seed reports it left the existing cache alone
    And the user npm cache still contains the original package
    And the user npm cache does not contain the marker package

  Scenario: seeding silently no-ops when no bundled cache is present
    Given no bundled npm cache directory exists
    And no user npm cache directory exists yet
    When I seed the user npm cache from the bundled cache
    Then the seed reports it left the existing cache alone
