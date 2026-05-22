Feature: Local zip module source

  The local-zip module source extracts a .zip into a temp directory and
  hands the module root to the caller. GitHub "Download ZIP" archives
  wrap everything in a single top-level folder named after the repo;
  the wrapper-folder detection unwraps it so `bmad-method install
  --custom-source` receives the module root directly.

  Scenario: descends into a single wrapper folder
    Given a directory containing exactly one subdirectory "repo-main"
    When I ask for its module root
    Then the module root is the "repo-main" subdirectory

  Scenario: stays put when the directory has multiple top-level entries
    Given a directory containing files "a.txt" and "b.txt"
    When I ask for its module root
    Then the module root is the directory itself

  Scenario: ignores a __MACOSX sibling when detecting the wrapper
    Given a directory containing exactly one subdirectory "repo-main" plus a __MACOSX sibling
    When I ask for its module root
    Then the module root is the "repo-main" subdirectory

  Scenario: stays put when the sole entry is a file rather than a directory
    Given a directory containing exactly one file "only.txt"
    When I ask for its module root
    Then the module root is the directory itself

  Scenario: rejects an empty zip path
    Given an empty zip path
    When I extract the zip
    Then it fails with a "not configured" error

  Scenario: rejects a missing zip file
    Given a zip path that does not exist
    When I extract the zip
    Then it fails with a "zip not found" error
