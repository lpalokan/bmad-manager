# Sharing skills with your team: Global Skill Sync

BMad Manager can pull a curated set of **skills** from a private GitHub
repository into every project you open — in both **Claude Code** and **Codex**.
This lets one person (the **key user**) maintain an organisation's skills in one
place, and everyone else sync them down with a single click.

This guide has two parts:

- **Part 1 — Key user:** create the private skills repo, add your skills, and
  invite your team.
- **Part 2 — Team member:** point BMad Manager at the repo and sync.

---

## How it works (read this first)

Each sync clones (or hard-updates) the repo into a **`managed/`** subfolder of
your global skills directory:

| Tool        | Synced into                         |
| ----------- | ----------------------------------- |
| Claude Code | `~/.claude/skills/managed/`         |
| Codex       | `~/.codex/skills/managed/`          |

Key points:

- The **`managed/` folder is owned by the sync.** Every sync hard-resets it to
  match the repo exactly, so **any local edits inside `managed/` are
  discarded.** Treat it as read-only.
- **Your personal skills are safe.** Anything directly under `~/.claude/skills/`
  or `~/.codex/skills/` (i.e. *not* inside `managed/`) is never touched.
- The two buttons are **independent** — click only the one for the tool you use.
- The repo is **private**, so each person authenticates with their own
  read-only **GitHub token**, stored securely on their machine (macOS Keychain;
  Windows: a protected per-user file) — never in `settings.json`.

---

## Part 1 — Key user: set up the skills repo

### 1. Create a private repository

1. On GitHub, click **New repository**.
2. Name it something memorable, e.g. `bmad-skills`.
3. Set visibility to **Private**.
4. Create the repository.

### 2. Add your skills

A skill is a folder containing a `SKILL.md` (plus any supporting files). Lay the
repo out so the folders sit at the repo root — they'll land directly inside each
user's `managed/` folder:

```
bmad-skills/
├── my-first-skill/
│   └── SKILL.md
├── another-skill/
│   ├── SKILL.md
│   └── helper.py
└── README.md          (optional, ignored by the tools)
```

Commit and push to the branch you want everyone to track (default: `main`):

```
git clone https://github.com/your-org/bmad-skills.git
cd bmad-skills
# add skill folders…
git add -A
git commit -m "Add initial skills"
git push origin main
```

To update skills later, just push new commits — team members pick them up the
next time they hit **Sync**.

> **Branch tip:** most teams keep everything on `main`. If you want to stage
> changes, push to a `release` branch and tell your team to set that branch in
> Settings.

### 3. Invite your team

Give each teammate **read-only** access to the repo:

1. Repo → **Settings → Collaborators** (or **Teams**, for an org).
2. **Add people**, enter their GitHub usernames, and grant the **Read** role.
3. They'll receive an invitation to accept.

### 4. Tell your team how to authenticate

Each member needs a **fine-grained personal access token (PAT)** scoped to *just
this repo* with read-only contents. Share the snippet in
[Part 2, step 2](#2-create-a-read-only-github-token) below, substituting your
repo's name.

> **Per-user tokens are recommended** so access can be revoked individually and
> nothing is shared in chat. If you'd rather distribute a single shared token,
> create one fine-grained PAT yourself (steps below) and send it over a secure
> channel — but you'll have to rotate it for everyone if it leaks.

---

## Part 2 — Team member: sync the skills

### 1. Accept the invitation

Accept the repo invitation from the key user (check your email or
`https://github.com/notifications`). You can't sync a repo you can't read.

### 2. Create a read-only GitHub token

1. Go to **GitHub → Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**.
2. **Token name:** e.g. `bmad-skills read`.
3. **Expiration:** pick a sensible window (you can regenerate later).
4. **Resource owner:** the org/user that owns the skills repo.
5. **Repository access → Only select repositories →** choose the skills repo
   (e.g. `your-org/bmad-skills`).
6. **Permissions → Repository permissions → Contents → Read-only.** (That's the
   only permission needed.)
7. **Generate token** and copy it — GitHub shows it only once.

### 3. Configure BMad Manager

1. Open **Settings** (the ⚙ icon).
2. Under **Global skills repository**:
   - **Skills repo URL:** the HTTPS URL, e.g.
     `https://github.com/your-org/bmad-skills`
   - **Branch:** leave as `main` unless the key user told you otherwise.
   - **GitHub token 🔒:** paste your token and click **Save token**.
     - macOS stores it in your **Keychain**; Windows in a protected per-user
       file. It is **never** written to `settings.json`.
3. Click **Done**.

### 4. Sync

On the main window, in the **Skills** row, click:

- **Sync to Claude Code** — pulls into `~/.claude/skills/managed/`
- **Sync to Codex** — pulls into `~/.codex/skills/managed/`

Click only the button(s) for the tool(s) you use. Git's output streams into the
output panel; on success the skills are immediately available in new sessions of
that tool. Re-run any time to pick up the latest changes.

---

## Troubleshooting

The output panel shows git's own error. Common cases:

| Message                                  | Cause / fix                                                                 |
| ---------------------------------------- | --------------------------------------------------------------------------- |
| `Set a GitHub token in Settings first.`  | No token stored — add one in Settings (Part 2, step 3).                      |
| `Set a skills repo URL in Settings first.` | The Skills repo URL field is empty.                                       |
| `Authentication failed` / `403`          | Token is wrong, expired, or lacks **Contents: Read** on this repo. Regenerate it and check the repository scope. |
| `Repository not found` / `404`           | URL typo, or you haven't been granted read access — ask the key user.       |
| `Remote branch <x> not found`            | The branch in Settings doesn't exist on the repo. Confirm it with the key user (usually `main`). |

Other notes:

- **Lost local edits in `managed/`?** Expected — that folder is hard-reset on
  every sync. Put personal skills *outside* `managed/`.
- **Changing the branch** in Settings and re-syncing switches the managed clone
  to that branch's latest commit.
- **Rotating a token:** generate a new one, paste it, and **Save token** again
  (this overwrites the old one). **Clear** removes it entirely.
