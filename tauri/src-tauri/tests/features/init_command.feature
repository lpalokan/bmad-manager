Feature: Init command substitution and shell quoting

  The init command template carries three placeholders ({PROJECT_PATH},
  {MODULE_PATH}, {PROJECT_NAME}) that get substituted at project-creation
  time. On Windows, paths must be wrapped in double quotes (cmd.exe
  does not honour single quotes), so the substitution rewrites the
  Swift defaults' single-quoted placeholders to double-quoted ones
  without persisting the change to settings.json.

  Scenario: substitutes all three placeholders
    Given the init command template "init {PROJECT_NAME} at {PROJECT_PATH} from {MODULE_PATH}"
    When I substitute with project "demo", project path "/p/demo", module path "/m"
    Then the substituted command is "init demo at /p/demo from /m"

  Scenario: leaves single-quoted placeholders alone on POSIX
    Given the init command template "npx bmad install --custom-source '{MODULE_PATH}' --directory '{PROJECT_PATH}'"
    When I substitute for POSIX with project "demo", project path "/p/demo", module path "/m"
    Then the substituted command is "npx bmad install --custom-source '/m' --directory '/p/demo'"

  Scenario: shell-quotes a plain path on POSIX
    When I POSIX shell-quote "/Users/me/Projects/foo"
    Then the result is "'/Users/me/Projects/foo'"

  Scenario: shell-quotes a path with spaces on POSIX
    When I POSIX shell-quote "/Users/me/My Project"
    Then the result is "'/Users/me/My Project'"
