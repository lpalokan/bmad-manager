Feature: Company context discovery and import

  Mirrors the Swift CompanyContextService: existing projects are scanned
  for a company-context folder under `_bmad-output/company-context/`
  (preferred) or a top-level `company-context/` fallback. Every file there
  is part of the context — the canonical names (icp.md, positioning.md,
  brand-voice.md, kpis.md, tech-stack.md) first, then any extra files the
  user added — so a new project can be seeded with the complete folder
  instead of starting from scratch.

  # --- Resolution ---

  Scenario: finds a context under _bmad-output/company-context
    Given a project "acme" with context files "icp.md, kpis.md" under "_bmad-output/company-context"
    When I resolve the context of project "acme"
    Then a context from project "acme" is found
    And the context directory ends with "_bmad-output/company-context"

  Scenario: falls back to a top-level company-context folder
    Given a project "acme" with context files "icp.md" under "company-context"
    When I resolve the context of project "acme"
    Then a context from project "acme" is found
    And the context directory ends with "company-context"

  Scenario: prefers the _bmad-output location over the top-level fallback
    Given a project "acme" with context files "icp.md" under "_bmad-output/company-context"
    And the project "acme" also has context files "positioning.md" under "company-context"
    When I resolve the context of project "acme"
    Then the context directory ends with "_bmad-output/company-context"
    And the context files are exactly "icp.md"

  Scenario: treats any files in a context folder as a context
    Given a project "extras" with context files "bootstrap-summary.md, notes.txt" under "_bmad-output/company-context"
    When I resolve the context of project "extras"
    Then a context from project "extras" is found
    And the context files are exactly "bootstrap-summary.md, notes.txt"

  Scenario: lists all files, canonical names first then extras alphabetically
    Given a project "acme" with context files "tech-stack.md, icp.md, bootstrap-summary.md, brand-voice.md" under "_bmad-output/company-context"
    When I resolve the context of project "acme"
    Then the context files are exactly "icp.md, brand-voice.md, tech-stack.md, bootstrap-summary.md"

  Scenario: contexts sort by project name regardless of input order
    Given a project "zebra" with context files "icp.md" under "_bmad-output/company-context"
    And a project "Alpha" with context files "kpis.md" under "_bmad-output/company-context"
    And a project "mango" with no context files
    When I resolve the contexts of projects "zebra, Alpha, mango"
    Then the resolved context project names are exactly "Alpha, zebra"

  # --- Display ---

  Scenario: display name is the project name with a folder marker
    Given a project "acme" with context files "icp.md, positioning.md, brand-voice.md, kpis.md, tech-stack.md" under "_bmad-output/company-context"
    When I resolve the context of project "acme"
    Then the context display name is "acme 📂"

  Scenario: display name has no file-count hint for a partial context
    Given a project "acme" with context files "icp.md, kpis.md" under "_bmad-output/company-context"
    When I resolve the context of project "acme"
    Then the context display name is "acme 📂"

  # --- Skills repo (GitHub) contexts ---

  Scenario: discovers contexts published in the skills repo context folder
    Given a skills repo context "globex" with files "positioning.md"
    And a skills repo context "acme" with files "icp.md, kpis.md"
    When I resolve the skills repo contexts
    Then the resolved context project names are exactly "acme, globex"
    And the resolved contexts all come from the skills repo

  Scenario: a github context display name carries the github marker
    Given a skills repo context "acme" with files "icp.md, positioning.md, brand-voice.md, kpis.md, tech-stack.md"
    When I resolve the skills repo contexts
    Then the github context "acme" display name is "acme 🐙"

  Scenario: discovers a skills repo context folder holding any file
    Given a skills repo context "notes" with files "readme.md"
    When I resolve the skills repo contexts
    Then the resolved context project names are exactly "notes"
    And the resolved contexts all come from the skills repo

  # --- Import ---

  Scenario: import copies the context files into the new project
    Given a project "acme" with context files "icp.md, kpis.md" under "_bmad-output/company-context"
    And an empty project "fresh"
    When I import the context of "acme" into project "fresh"
    Then project "fresh" contains context files "icp.md, kpis.md"

  Scenario: import carries every file over, including user-added extras
    Given a project "acme" with context files "icp.md, bootstrap-summary.md" under "_bmad-output/company-context"
    And an empty project "fresh"
    When I import the context of "acme" into project "fresh"
    Then project "fresh" contains context files "icp.md, bootstrap-summary.md"

  Scenario: import leaves existing destination files untouched
    Given a project "acme" with context files "icp.md, kpis.md" under "_bmad-output/company-context"
    And an empty project "fresh"
    And project "fresh" already has a context file "icp.md" with content "do not clobber"
    When I import the context of "acme" into project "fresh"
    Then the context file "icp.md" in project "fresh" still has content "do not clobber"
    And project "fresh" contains context files "icp.md, kpis.md"

  Scenario: import fails with a readable error when a source file vanished
    Given a project "acme" with context files "icp.md" under "_bmad-output/company-context"
    And an empty project "fresh"
    And the context file "icp.md" of project "acme" has vanished
    When I import the context of "acme" into project "fresh"
    Then the import fails mentioning "icp.md"

  # --- Project creation pipeline ---

  Scenario: create imports the selected context after the init command succeeds
    Given a project "acme" with context files "icp.md, kpis.md" under "_bmad-output/company-context"
    And creation settings whose init command succeeds
    When I create a project "fresh" importing the context of "acme"
    Then the creation succeeds
    And project "fresh" contains context files "icp.md, kpis.md"

  Scenario: create without a context selection does not create a context folder
    Given creation settings whose init command succeeds
    When I create a project "fresh" without importing a context
    Then the creation succeeds
    And project "fresh" has no context folder

  Scenario: create does not import the context when the init command fails
    Given a project "acme" with context files "icp.md" under "_bmad-output/company-context"
    And creation settings whose init command fails
    When I create a project "fresh" importing the context of "acme"
    Then the creation fails mentioning "exited with code"
    And project "fresh" has no context folder

  Scenario: create surfaces a context import failure with the source project name
    Given a project "acme" with context files "icp.md" under "_bmad-output/company-context"
    And creation settings whose init command succeeds
    And the context file "icp.md" of project "acme" has vanished
    When I create a project "fresh" importing the context of "acme"
    Then the creation fails mentioning "importing the context from 'acme' failed"
