Feature: Global skills repository sync
  Pure helpers behind the "Sync to Claude Code / Codex" buttons: where the repo
  is cloned, where skills are linked, token-safe auth, and settings persistence.

  Scenario: Claude Code skills live under .claude/skills
    When I compute the skills root for "claude" under home "/home/me"
    Then the skills path is "/home/me/.claude/skills"

  Scenario: the cloned repo lives in a hidden sibling, not under skills
    When I compute the managed repo dir for "codex" under home "/home/me"
    Then the skills path is "/home/me/.codex/skills-managed"

  Scenario: the auth header carries the token without leaking it
    When I build the skills auth header for token "ghp_supersecret"
    Then the skills auth header starts with "AUTHORIZATION: basic "
    And the skills auth header does not contain "ghp_supersecret"

  Scenario: skills settings round-trip through JSON
    Given skills settings with repo "https://github.com/acme/skills" and branch "release"
    When I encode and decode the skills settings
    Then the decoded skills repo URL is "https://github.com/acme/skills"
    And the decoded skills repo branch is "release"

  Scenario: legacy settings without skills fields default the branch to main
    Given a legacy settings JSON without skills fields
    When I decode the legacy settings
    Then the decoded skills repo URL is ""
    And the decoded skills repo branch is "main"

  # --- Repointing an existing clone when the configured repo changes ---
  #
  # The clone is only made once; every later sync is a `fetch origin` + reset.
  # Nothing used to compare that `origin` against the configured URL, so
  # changing the skills repo in Settings silently kept syncing the old one —
  # a sync that reported success while serving another repo's skills and
  # contexts.

  Scenario: the origin URL is read from an existing clone
    Given a skills clone whose origin is "https://github.com/acme/old-skills"
    When I read the clone's origin URL
    Then the clone origin URL is "https://github.com/acme/old-skills"

  Scenario: a clone with no git config reports no origin URL
    Given a skills clone with no git config
    When I read the clone's origin URL
    Then the clone has no origin URL

  Scenario: a trailing .git or slash does not count as a different remote
    When I compare remote "https://github.com/acme/skills" with "https://github.com/acme/skills.git/"
    Then the remotes are the same

  Scenario: a different repository counts as a different remote
    When I compare remote "https://github.com/acme/skills" with "https://github.com/acme/other"
    Then the remotes are not the same

  Scenario: repointing a clone rewrites its origin URL
    When I build the repoint args for "https://github.com/acme/new-skills"
    Then the git args are "remote set-url origin https://github.com/acme/new-skills"

  # --- Which clone the shared contexts are read from ---
  #
  # Both tools clone the same repo into their own hidden dir. Picking "the
  # first clone that has any contexts" served another repo's context packs
  # whenever a clone was left pointing at the old URL.

  Scenario: shared contexts come from the clone matching the configured repo
    Given a "claude" clone of "https://github.com/acme/old-skills" holding context "legacy-pack"
    And a "codex" clone of "https://github.com/acme/new-skills" holding context "current-pack"
    When I list the shared contexts for repo "https://github.com/acme/new-skills"
    Then the shared context names are "current-pack"

  Scenario: a clone pointing at another repo is not used for shared contexts
    Given a "claude" clone of "https://github.com/acme/old-skills" holding context "legacy-pack"
    When I list the shared contexts for repo "https://github.com/acme/new-skills"
    Then there are no shared contexts

  Scenario: a clone whose origin cannot be read is still used
    Given a "claude" clone with an unreadable origin holding context "legacy-pack"
    When I list the shared contexts for repo "https://github.com/acme/new-skills"
    Then the shared context names are "legacy-pack"

  Scenario: with no repo configured any clone still provides contexts
    Given a "claude" clone of "https://github.com/acme/old-skills" holding context "legacy-pack"
    When I list the shared contexts for repo ""
    Then the shared context names are "legacy-pack"

  # --- Overlapping syncs ---
  #
  # Startup auto-sync and the ⟳ button both call the same sync. Two runs over
  # the same link set race: one removes the links the other just created, and
  # the loser fails with "a link of that name already exists".

  Scenario: a second sync waits for the one already running
    Given a skills sync gate
    When two syncs run through the gate at the same time
    Then the syncs did not overlap

  Scenario: a tool that has never synced offers no clone
    Given a "claude" clone of "https://github.com/acme/skills" holding context "pack"
    When I list the clones for repo "https://github.com/acme/skills"
    Then one clone is offered
