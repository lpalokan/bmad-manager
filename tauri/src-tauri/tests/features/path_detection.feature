Feature: Detecting coding-agent executables on PATH

  The Settings dialog tells the user whether the configured coding-agent
  commands (claude, opencode, pi) are reachable via PATH so they can
  either trust the defaults or point the app at an explicit binary. The
  detection service must answer "yes / here's where" or "no" without
  shelling out and without surprising users when they pass an absolute
  path instead of a bare command name.

  Scenario: a bare command on PATH resolves to an absolute path
    Given a PATH directory containing an executable named "ficticious-agent"
    When I detect the command "ficticious-agent" against that PATH
    Then the detection returns the absolute path to that executable

  Scenario: a bare command missing from PATH is reported as not found
    Given a PATH directory with no matching executable
    When I detect the command "definitely-not-installed-9999" against that PATH
    Then the detection returns nothing

  Scenario: an absolute path that exists is returned as-is
    Given a file that exists on disk
    When I detect that file's absolute path against an empty PATH
    Then the detection returns that same absolute path

  Scenario: an absolute path that does not exist is reported as not found
    When I detect the command "/no/such/binary/anywhere" against an empty PATH
    Then the detection returns nothing

  Scenario: a blank command is reported as not found
    When I detect the command "   " against an empty PATH
    Then the detection returns nothing
