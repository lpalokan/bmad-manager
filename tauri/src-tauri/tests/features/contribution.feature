Feature: Contribute skills and contexts as pull requests

  Users can propose ADDITIONS to the shared skills/context repo: their own
  (non-managed) skills and their project contexts are gathered, staged under
  `skills/<name>/` and `context/<name>/`, and opened as a pull request. This
  covers the observable, network-free pieces; the GitHub choreography is unit
  tested with a fake client.

  # --- Repo URL parsing ---

  Scenario: parses owner and repo from the skills repo URL
    When I parse the contribution repo URL "https://github.com/acme/skills.git"
    Then the parsed owner is "acme" and repo is "skills"

  Scenario: rejects a non-github skills repo URL
    When I parse the contribution repo URL "https://gitlab.com/acme/skills"
    Then the repo URL is not parseable

  # --- Enumerating contributable skills ---

  Scenario: offers personal skills but not managed links
    Given a personal skill "my-skill" in the skills folder
    And a managed linked skill "team-skill" in the skills folder
    When I list contributable skills
    Then the contributable skills are exactly "my-skill"

  # --- Staging files ---

  Scenario: stages skill files under the skills folder
    Given a personal skill "my-skill" in the skills folder
    When I stage the contribution files for skill "my-skill"
    Then a staged file path is "skills/my-skill/SKILL.md"

  Scenario: stages only recognized context files under the context folder
    Given a contributable context "acme" with files "icp.md, notes.txt"
    When I stage the contribution files for context "acme"
    Then a staged file path is "context/acme/icp.md"
    And no staged file path is "context/acme/notes.txt"

  # --- Name safety ---

  Scenario: rejects an unsafe target name
    When I sanitize the contribution name "../evil"
    Then the contribution name is rejected

  Scenario: accepts and trims a safe target name
    When I sanitize the contribution name "  acme-corp  "
    Then the sanitized contribution name is "acme-corp"
