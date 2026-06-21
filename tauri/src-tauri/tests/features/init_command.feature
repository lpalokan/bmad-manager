Feature: Init command substitution and shell quoting

  The init command template carries the placeholders {PROJECT_PATH},
  {MODULE_SOURCE}, {MODULE_PATH}, and {PROJECT_NAME} that get substituted at
  project-creation time. {MODULE_SOURCE} is the value handed to
  --custom-source: the repo URL for a git source (so the installer records
  repoUrl + a real version) or the local module path for a zip source. On
  Windows, paths/values must be wrapped in double quotes (cmd.exe does not
  honour single quotes), so the substitution rewrites the Swift defaults'
  single-quoted placeholders to double-quoted ones without persisting the
  change to settings.json.

  Scenario: substitutes all placeholders
    Given the init command template "init {PROJECT_NAME} at {PROJECT_PATH} from {MODULE_SOURCE} ({MODULE_PATH})"
    When I substitute with project "demo", project path "/p/demo", module source "https://github.com/o/r@v1", module path "/m"
    Then the substituted command is "init demo at /p/demo from https://github.com/o/r@v1 (/m)"

  Scenario: substitutes the module-source placeholder on POSIX
    Given the init command template "npx bmad install --custom-source '{MODULE_SOURCE}' --directory '{PROJECT_PATH}'"
    When I substitute for POSIX with project "demo", project path "/p/demo", module source "https://github.com/o/r@v2.0.2", module path "/m"
    Then the substituted command is "npx bmad install --custom-source 'https://github.com/o/r@v2.0.2' --directory '/p/demo'"

  Scenario: rewrites module-source single quotes to double on Windows
    Given the init command template "npx bmad install --custom-source '{MODULE_SOURCE}' --directory '{PROJECT_PATH}'"
    When I substitute for Windows with project "demo", project path "C:\p\demo", module source "https://github.com/o/r", module path "C:\m"
    Then the substituted command is "npx bmad install --custom-source "https://github.com/o/r" --directory "C:\p\demo""

  Scenario: pins a git URL to an explicit ref
    When I pin url "https://github.com/o/r" to ref "v1.2.3"
    Then the result is "https://github.com/o/r@v1.2.3"

  Scenario: picks the latest semver tag when no ref is set
    When I pick the latest semver tag from "v1.0.1, v1.0.2, v1.0.3, v2.0.2"
    Then the result is "v2.0.2"

  Scenario: ignores non-semver tags when picking the latest
    When I pick the latest semver tag from "latest, nightly, v1.4.0"
    Then the result is "v1.4.0"

  Scenario: shell-quotes a plain path on POSIX
    When I POSIX shell-quote "/Users/me/Projects/foo"
    Then the result is "'/Users/me/Projects/foo'"

  Scenario: shell-quotes a path with spaces on POSIX
    When I POSIX shell-quote "/Users/me/My Project"
    Then the result is "'/Users/me/My Project'"
