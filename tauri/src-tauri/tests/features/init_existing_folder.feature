Feature: Initialize BMAD into an existing folder

  Besides creating a brand-new folder under the projects root, the user can
  point init at a folder that already exists (e.g. add BMAD to an existing
  project). The folder is used as-is — no must-not-exist guard, no fresh
  mkdir — and the project name is derived from the folder's basename.

  Before running init the UI inspects the target so it can confirm a
  potentially destructive overwrite: a non-empty folder is flagged, and an
  existing BMAD install (a marker like bmad/.bmad/_cfg) is flagged more
  strongly. An empty folder proceeds without a prompt.

  Scenario: accepts an existing empty folder as the init target
    Given an existing folder "legacy-empty"
    When I prepare to initialize that folder
    Then the init target is accepted with name "legacy-empty"

  Scenario: rejects a path that is not an existing directory
    Given a path "ghost" that does not exist
    When I prepare to initialize that folder
    Then the init target is rejected as not a folder

  Scenario: an empty folder needs no overwrite confirmation
    Given an existing folder "fresh"
    When I inspect that folder as an init target
    Then the init target reports it exists
    And the init target reports it is empty
    And the init target reports no BMAD install

  Scenario: a non-empty folder is flagged for confirmation
    Given an existing folder "has-files"
    And the folder contains a file "notes.txt"
    When I inspect that folder as an init target
    Then the init target reports it exists
    And the init target reports it is not empty
    And the init target reports no BMAD install

  Scenario: an existing BMAD install is flagged more strongly
    Given an existing folder "already-bmad"
    And the folder contains a "bmad" marker directory
    When I inspect that folder as an init target
    Then the init target reports it is not empty
    And the init target reports a BMAD install
