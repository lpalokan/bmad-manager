# Create a skills & context repository for your company

A single private GitHub repo holds two things every project can pull from:

- **Skills** — reusable Claude Code / Codex skills.
- **Contexts** — company-context bundles (ICP, positioning, brand voice, KPIs,
  tech stack) a new project can be seeded from.

BMad Manager **reads** this repo automatically (on startup and the Refresh
button) and lets people **propose additions** to it as pull requests. This guide
sets the repo up so both work. You only do this once.

> For the day-to-day sync experience see [global-skills-sync.md](global-skills-sync.md).
> For contributing additions from the app see
> [contributing-from-bmad-manager.md](contributing-from-bmad-manager.md).

---

## 1. Create the repository

1. On GitHub, **New repository**.
2. Name it, e.g. `bmad-skills`.
3. Visibility **Private**.
4. Create.

## 2. Lay out the folders

Two top-level folders — **`skills/`** and **`context/`**:

```
bmad-skills/
├── skills/
│   ├── my-first-skill/
│   │   └── SKILL.md            (required for each skill)
│   └── another-skill/
│       ├── SKILL.md
│       └── helper.py
├── context/
│   └── acme-corp/
│       ├── icp.md              (one or more of the five below)
│       ├── positioning.md
│       ├── brand-voice.md
│       ├── kpis.md
│       └── tech-stack.md
└── README.md                  (optional, ignored by the app)
```

Rules the app applies:

- A **skill** is any folder under `skills/` that contains a `SKILL.md`.
- A **context** is any folder under `context/` containing at least one of the
  five recognized files: `icp.md`, `positioning.md`, `brand-voice.md`,
  `kpis.md`, `tech-stack.md`. Anything else in the folder is ignored on import.
- The folder name is what people see in the app (repo contexts are badged 🐙;
  project-local ones 📂).

> Older repos that keep skills at the repo root still work (the app falls back
> to the root), but new repos should use `skills/` so `context/` can sit beside
> it.

Seed it and push to `main`:

```
git clone https://github.com/your-org/bmad-skills.git
cd bmad-skills
git add -A
git commit -m "Initial skills and contexts"
git push origin main
```

## 3. Protect `main`

This is what guarantees nobody can change the repo except through a reviewed
pull request — even someone holding a write-capable token. There is **no token
permission** for "branches except `main`"; this ruleset is what draws that line.

GitHub → repo **Settings → Rules → Rulesets → New branch ruleset**:

- **Target branches:** the default branch (`main`).
- **Require a pull request before merging** (require at least 1 approval).
- **Block force pushes**.
- **Restrict deletions**.
- Leave the bypass list empty (i.e. *do not allow bypassing*).

Result: branches and PRs are allowed; direct writes to `main` are not.

## 4. (Optional) Enforce "additions only"

A write token can still place edits to existing files *on a branch* inside a PR.
If you want that rejected automatically rather than caught in review, add a
`pull_request` check that fails when the diff touches anything outside a
newly-added `skills/<name>/` or `context/<name>/` path.

`.github/workflows/additions-only.yml`:

```yaml
name: additions-only
on: pull_request
jobs:
  guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Reject edits/deletes of existing files
        run: |
          base="${{ github.event.pull_request.base.sha }}"
          if git diff --name-status "$base"...HEAD | grep -vE '^A[[:space:]]+(skills|context)/'; then
            echo "PRs may only ADD files under skills/ or context/."
            exit 1
          fi
```

Then mark this check **required** in the ruleset.

## 5. Issue access tokens

Two roles, both **fine-grained PATs scoped to this one repo**. Each person uses
their own token (don't share one between people if you want per-person
revocation). A token can never exceed the person's own access, so the protection
above holds regardless of token scope.

**Consumers (sync only) — read-only:**

- GitHub → **Settings → Developer settings → Personal access tokens →
  Fine-grained → Generate**.
- **Resource owner:** the account/org that owns the repo.
- **Repository access → Only select repositories →** this repo.
- **Permissions → Contents: Read-only.**

**Contributors (propose additions) — read + write + PRs:**

- Same as above, but **Permissions → Contents: Read and write** *and*
  **Pull requests: Read and write**.

With `main` protected (step 3), a contributor token can only create branches and
open PRs — it cannot change `main`. No bot account and no forks are involved.

## 6. Point BMad Manager at it

Tell each person to open **Settings → Global skills repository** and set:

- **Skills repo URL:** `https://github.com/your-org/bmad-skills`
- **Branch:** `main`
- **GitHub token 🔒:** their read-only token (consumers) — stored in the OS
  credential store, never in `settings.json`.
- **Contributor token 🔒 (optional):** their read-write token (contributors).
  Use **Test access** to confirm it can push before contributing.

On startup and Refresh the app syncs skills and lists the repo's contexts
automatically.

## Checklist

- [ ] Private repo created
- [ ] `skills/` and `context/` folders, correct file conventions, pushed to `main`
- [ ] `main` ruleset: require PR + approval, block force-push, restrict deletions, no bypass
- [ ] (Optional) additions-only CI check, marked required
- [ ] Read-only token recipe shared with consumers
- [ ] Read-write (Contents + Pull requests) token recipe shared with contributors
- [ ] Repo URL shared with the team
