Feature: Secure skills-repo token storage
  The skills-repo GitHub token is kept in the OS secure credential store via the
  platform layer (Windows Credential Manager in production; the macOS app uses
  the Keychain), and never inside settings.json. On dev/CI builds with no OS
  keystore wired up, the platform stub falls back to a per-user, owner-only file
  next to settings.json — but the token is still kept out of settings.json and is
  never left readable by other users on the machine.

  Scenario: a stored token round-trips
    When I store the github token "ghp_supersecret123"
    Then a github token is reported as stored
    And reading the github token returns "ghp_supersecret123"

  Scenario: a stored token is trimmed of surrounding whitespace
    When I store the github token "  ghp_padded  "
    Then reading the github token returns "ghp_padded"

  Scenario: storing an empty token clears any stored value
    Given I have stored the github token "ghp_supersecret123"
    When I store the github token "   "
    Then no github token is reported as stored

  Scenario: clearing the token removes it
    Given I have stored the github token "ghp_supersecret123"
    When I clear the github token
    Then no github token is reported as stored

  Scenario: the token is never written into settings.json
    When I store the github token "ghp_supersecret123"
    Then no settings.json file is created in the token store location

  Scenario: the token is never left readable by other users on the machine
    When I store the github token "ghp_supersecret123"
    Then the token is not stored in a world-readable plaintext file
