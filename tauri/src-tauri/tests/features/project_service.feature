Feature: Project folder validation and listing

  ProjectService enforces the folder-naming rules from the macOS app
  (no slashes, colons, leading dots, empty names) and lists project
  folders under the configured root with optional sort orderings.

  Scenario: rejects an empty name
    Given an empty projects root directory
    When I try to create a project named ""
    Then it fails with an "invalid name" error

  Scenario: rejects a whitespace-only name
    Given an empty projects root directory
    When I try to create a project named "   "
    Then it fails with an "invalid name" error

  Scenario: rejects a slash in the name
    Given an empty projects root directory
    When I try to create a project named "foo/bar"
    Then it fails with an "invalid name" error

  Scenario: rejects a leading dot
    Given an empty projects root directory
    When I try to create a project named ".hidden"
    Then it fails with an "invalid name" error

  Scenario: trims surrounding whitespace
    Given an empty projects root directory
    When I create a project named "  spaced  "
    Then a folder named "spaced" exists at the projects root

  Scenario: rejects a duplicate project
    Given an empty projects root directory
    And a project named "dup" already exists
    When I try to create a project named "dup"
    Then it fails with a "project exists" error

  Scenario: creates the root folder if it is missing
    Given a nonexistent projects root directory
    When I create a project named "p1"
    Then the projects root now exists
    And a folder named "p1" exists at the projects root

  Scenario: lists projects sorted by name ascending
    Given projects named "beta", "alpha", "Charlie" exist
    When I list projects sorted by "nameAscending"
    Then the listed names are exactly "alpha", "beta", "Charlie"

  Scenario: lists projects skipping loose files
    Given a project named "alpha" exists
    And a loose file "loose.txt" exists at the projects root
    When I list projects sorted by "nameAscending"
    Then the listed names are exactly "alpha"

  Scenario: lists projects from a missing root returns empty
    Given a nonexistent projects root directory
    When I list projects sorted by "nameAscending"
    Then the listed names are exactly
