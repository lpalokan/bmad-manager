Feature: Company context discovery and import

  Mirrors the Swift CompanyContextService: existing projects are scanned
  for a company-context folder under `output/company-context/` (the
  canonical marketing-growth layout), then the legacy
  `_bmad-output/company-context/`, then a top-level `company-context/`
  fallback. Every file there is part of the context — the canonical names
  (icp.md, positioning.md, brand-voice.md, kpis.md, tech-stack.md) first,
  then any extra files the user added — so a new project can be seeded with
  the complete folder instead of starting from scratch. Reading is broad;
  writing is always to `output/company-context/`.

  # --- Resolution ---

  Scenario: finds a context under output/company-context
    Given a project "acme" with context files "icp.md, kpis.md" under "output/company-context"
    When I resolve the context of project "acme"
    Then a context from project "acme" is found
    And the context directory ends with "output/company-context"

  Scenario: finds a context under the legacy _bmad-output/company-context
    Given a project "acme" with context files "icp.md, kpis.md" under "_bmad-output/company-context"
    When I resolve the context of project "acme"
    Then a context from project "acme" is found
    And the context directory ends with "_bmad-output/company-context"

  Scenario: falls back to a top-level company-context folder
    Given a project "acme" with context files "icp.md" under "company-context"
    When I resolve the context of project "acme"
    Then a context from project "acme" is found
    And the context directory ends with "company-context"

  Scenario: prefers output over the legacy _bmad-output location
    Given a project "acme" with context files "icp.md" under "output/company-context"
    And the project "acme" also has context files "positioning.md" under "_bmad-output/company-context"
    When I resolve the context of project "acme"
    Then the context directory ends with "output/company-context"
    And the context files are exactly "icp.md"

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

  Scenario: includes files in subfolders with their relative paths
    Given a project "acme" with context files "icp.md, research/notes.md, research/personas.md" under "_bmad-output/company-context"
    When I resolve the context of project "acme"
    Then the context files are exactly "icp.md, research/notes.md, research/personas.md"

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
  #
  # The write side is unconditional: whatever layout the source uses, the
  # seeded copy lands in the canonical `output/company-context/`. Nothing
  # is moved and no legacy folder is created (issue #96).

  Scenario: import copies the context files into the new project
    Given a project "acme" with context files "icp.md, kpis.md" under "_bmad-output/company-context"
    And an empty project "fresh"
    When I import the context of "acme" into project "fresh"
    Then project "fresh" contains context files "icp.md, kpis.md"

  Scenario: import writes into the canonical output folder
    Given a project "acme" with context files "icp.md, kpis.md" under "output/company-context"
    And an empty project "fresh"
    When I import the context of "acme" into project "fresh"
    Then project "fresh" contains context files "icp.md, kpis.md" under "output/company-context"
    And project "fresh" has no "_bmad-output" folder

  Scenario: a legacy source still seeds into the canonical output folder
    Given a project "acme" with context files "icp.md" under "_bmad-output/company-context"
    And an empty project "fresh"
    When I import the context of "acme" into project "fresh"
    Then project "fresh" contains context files "icp.md" under "output/company-context"
    And project "fresh" has no "_bmad-output" folder

  Scenario: import carries every file over, including user-added extras
    Given a project "acme" with context files "icp.md, bootstrap-summary.md" under "_bmad-output/company-context"
    And an empty project "fresh"
    When I import the context of "acme" into project "fresh"
    Then project "fresh" contains context files "icp.md, bootstrap-summary.md"

  Scenario: import recreates subfolders in the new project
    Given a project "acme" with context files "icp.md, research/notes.md" under "_bmad-output/company-context"
    And an empty project "fresh"
    When I import the context of "acme" into project "fresh"
    Then project "fresh" contains context files "icp.md, research/notes.md"

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

  # A new project installs with `--output-folder output` (issue #99) so core
  # and every module write under the same folder the company-context lives in.
  Scenario: create runs the init command with the output folder flag
    Given creation settings whose init command records its arguments
    When I create a project "fresh" without importing a context
    Then the creation succeeds
    And project "fresh" file "init-args.txt" contains "--output-folder output"

  Scenario: create surfaces a context import failure with the source project name
    Given a project "acme" with context files "icp.md" under "_bmad-output/company-context"
    And creation settings whose init command succeeds
    And the context file "icp.md" of project "acme" has vanished
    When I create a project "fresh" importing the context of "acme"
    Then the creation fails mentioning "importing the context from 'acme' failed"

  # --- Context drift vs the skills repo (issue #92) ---
  #
  # A project's company-context is copied from a skills-repo context at
  # create time and then falls behind when the maintainer edits that
  # context. Drift is read from the OKF `last_updated` date (always bumped
  # on edit); the project's source context is resolved from the OKF `tags`
  # slug its own files carry; a refresh overwrites the drifted files while
  # keeping project-only additions.

  Scenario: a project matching its source context reports no drift
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a project "investor-day" seeded from the "digital-workforce" skills repo context
    When I check whether project "investor-day" has a context update
    Then project "investor-day" reports no context update

  Scenario: an admin edit that bumps last_updated flags the project
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a project "investor-day" seeded from the "digital-workforce" skills repo context
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-07-03"
    When I check whether project "investor-day" has a context update
    Then project "investor-day" reports a context update is available

  Scenario: an older or equal source date is not drift
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-07-03"
    And a project "investor-day" seeded from the "digital-workforce" skills repo context
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-06-01"
    When I check whether project "investor-day" has a context update
    Then project "investor-day" reports no context update

  Scenario: a changed dateless file is caught by the content fallback
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And the skills repo context "digital-workforce" also has dateless OKF file "index.md" containing "one link"
    And a project "investor-day" seeded from the "digital-workforce" skills repo context
    And the skills repo context "digital-workforce" dateless file "index.md" is edited to contain "two links"
    When I check whether project "investor-day" has a context update
    Then project "investor-day" reports a context update is available

  Scenario: a source context that added a new file flags the project
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a project "investor-day" seeded from the "digital-workforce" skills repo context
    And the skills repo context "digital-workforce" gains OKF file "kpis.md" dated "2026-06-26"
    When I check whether project "investor-day" has a context update
    Then project "investor-day" reports a context update is available

  Scenario: a project whose source context is no longer published is left alone
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a project "orphan" seeded from the "digital-workforce" skills repo context
    And the skills repo context "digital-workforce" is removed
    When I check whether project "orphan" has a context update
    Then project "orphan" reports no context update

  Scenario: refreshing overwrites drifted files with the skills repo version
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a project "investor-day" seeded from the "digital-workforce" skills repo context
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-07-03"
    When I refresh project "investor-day" from the skills repo
    Then project "investor-day" context file "positioning.md" is dated "2026-07-03"

  Scenario: refreshing adds new source files and keeps project-only files
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a project "investor-day" seeded from the "digital-workforce" skills repo context
    And project "investor-day" has a local context file "notes-local.md"
    And the skills repo context "digital-workforce" gains OKF file "kpis.md" dated "2026-07-03"
    When I refresh project "investor-day" from the skills repo
    Then project "investor-day" contains context files "positioning.md, kpis.md, notes-local.md"

  # A project still on the legacy layout is refreshed where it already
  # lives — the manager never relocates an existing bundle (issue #96).
  Scenario: refreshing a legacy _bmad-output project rewrites it in place
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a project "legacy" seeded from the "digital-workforce" skills repo context under "_bmad-output/company-context"
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-07-03"
    When I refresh project "legacy" from the skills repo
    Then project "legacy" contains context files "positioning.md" under "_bmad-output/company-context"
    And project "legacy" has no "output" folder

  # The canonical loop (issue #92): seeded in sync, admin bumps the date,
  # the project shows drift, a refresh brings it current, drift clears.
  Scenario: refreshing then re-checking clears the context update
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a project "investor-day" seeded from the "digital-workforce" skills repo context
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-07-03"
    When I refresh project "investor-day" from the skills repo
    And I check whether project "investor-day" has a context update
    Then project "investor-day" reports no context update

  # --- Resolving which context a project was seeded from (issue #103) ---
  #
  # OKF `tags` carry two different things: the pack's own identity slug and
  # subject keywords. A file that names another vertical as its subject must
  # not cost the project its upstream link, and a sub-pack bundled inside the
  # context folder must not outvote the pack the project was actually seeded
  # from. Resolution therefore takes a plurality vote across the context's
  # top-level files only. A marker written at seed time settles it outright,
  # so projects created from here on never depend on the vote.

  # These three seed without a marker (the `under` form copies files the way
  # a pre-#103 install left them), so the tag vote itself is under test.

  Scenario: a subject-matter tag naming another pack does not block resolution
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a skills repo context "healthcare" with OKF file "positioning.md" dated "2026-06-26"
    And a project "investor-day" seeded from the "digital-workforce" skills repo context under "output/company-context"
    And project "investor-day" has a local context file "offerings.md" tagged "digital-workforce, healthcare"
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-07-03"
    When I check whether project "investor-day" has a context update
    Then project "investor-day" reports a context update is available

  Scenario: a bundled sub-pack does not outvote the pack the project was seeded from
    Given a skills repo context "enterprise-public-sector" with OKF file "positioning.md" dated "2026-06-26"
    And a skills repo context "agent-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And the skills repo context "agent-workforce" gains OKF file "icp.md" dated "2026-06-26"
    And the skills repo context "agent-workforce" gains OKF file "kpis.md" dated "2026-06-26"
    And a project "gtm" seeded from the "enterprise-public-sector" skills repo context under "output/company-context"
    And project "gtm" bundles the "agent-workforce" skills repo context in a sub-folder
    And the skills repo context "enterprise-public-sector" file "positioning.md" is edited and dated "2026-07-03"
    When I check whether project "gtm" has a context update
    Then project "gtm" reports a context update is available

  Scenario: an evenly split vote stays unresolved
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a skills repo context "healthcare" with OKF file "positioning.md" dated "2026-06-26"
    And a project "split" seeded from the "digital-workforce" skills repo context under "output/company-context"
    And project "split" has a local context file "vertical.md" tagged "healthcare"
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-07-03"
    When I check whether project "split" has a context update
    Then project "split" reports no context update

  Scenario: the seed marker resolves the source even when the tag vote is tied
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a skills repo context "healthcare" with OKF file "positioning.md" dated "2026-06-26"
    And a project "marked" seeded from the "digital-workforce" skills repo context
    And project "marked" has a local context file "vertical.md" tagged "healthcare"
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-07-03"
    When I check whether project "marked" has a context update
    Then project "marked" reports a context update is available

  Scenario: seeding records the source marker
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a project "fresh" seeded from the "digital-workforce" skills repo context
    Then project "fresh" records "digital-workforce" as its context source

  Scenario: the seed marker is not treated as context content
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a project "fresh" seeded from the "digital-workforce" skills repo context
    When I resolve the context of project "fresh"
    Then the context files are exactly "positioning.md"

  # --- Backing up edits a refresh would overwrite (issue #103) ---
  #
  # A refresh overwrites every file belonging to the source pack. Anything the
  # user changed in one of those files is copied aside first, so an update can
  # never silently destroy their edit. Files that already match the source are
  # left alone and generate no backup noise.

  Scenario: refreshing backs up a locally edited file before overwriting it
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a project "investor-day" seeded from the "digital-workforce" skills repo context
    And project "investor-day" context file "positioning.md" is locally edited to contain "my own wording"
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-07-03"
    When I refresh project "investor-day" from the skills repo
    Then project "investor-day" has a context backup of "positioning.md" containing "my own wording"
    And project "investor-day" context file "positioning.md" is dated "2026-07-03"

  Scenario: refreshing an unchanged project backs nothing up
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a project "investor-day" seeded from the "digital-workforce" skills repo context
    And the skills repo context "digital-workforce" gains OKF file "kpis.md" dated "2026-06-26"
    When I refresh project "investor-day" from the skills repo
    Then project "investor-day" has no context backup

  # A file the source pack does not carry is outside the refresh entirely:
  # not overwritten, and so nothing to preserve.
  Scenario: a project-only file is never overwritten and never backed up
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a project "investor-day" seeded from the "digital-workforce" skills repo context
    And project "investor-day" has a local context file "notes-local.md"
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-07-03"
    When I refresh project "investor-day" from the skills repo
    Then project "investor-day" contains context files "positioning.md, notes-local.md"
    And project "investor-day" has no context backup of "notes-local.md"

  Scenario: backups are not treated as context content
    Given a skills repo context "digital-workforce" with OKF file "positioning.md" dated "2026-06-26"
    And a project "investor-day" seeded from the "digital-workforce" skills repo context
    And project "investor-day" context file "positioning.md" is locally edited to contain "my own wording"
    And the skills repo context "digital-workforce" file "positioning.md" is edited and dated "2026-07-03"
    When I refresh project "investor-day" from the skills repo
    And I resolve the context of project "investor-day"
    Then the context files are exactly "positioning.md"
