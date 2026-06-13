# Sharing skills with your team: Global Skill Sync

BMad Manager can pull a curated set of **skills** from a private GitHub
repository into every project you open — in both **Claude Code** and **Codex**.
This lets one person (the **key user**) maintain an organisation's skills in one
place, and everyone else sync them down with a single click.

There are two ways to give your team access, and you pick one:

- **Option A — Shared token (recommended for most teams).** You hand out one
  read-only token. Your colleagues **never log into GitHub, never accept an
  invitation, and never create a token** — they only ever use BMad Manager.
- **Option B — Per-user tokens.** Each colleague has their own GitHub access and
  token. More setup for them, but you get per-person audit and revocation.

This guide is in two parts:

- **Part 1 — Key user:** create the private skills repo, add your skills, and
  set up authentication (Option A or B).
- **Part 2 — Team member:** point BMad Manager at the repo and sync.

---

## How it works (read this first)

Claude Code and Codex only discover skills **one level deep** — a skill must be
a direct child of the skills folder (`~/.claude/skills/<skill>/SKILL.md`). So a
sync does two things: it clones the repo into a **hidden** folder the tool
doesn't scan, then **links each skill** into the skills folder as a direct child
(a junction on Windows, a symlink on macOS):

| Tool        | Repo cloned to (hidden)      | Skills linked into                 |
| ----------- | ---------------------------- | ---------------------------------- |
| Claude Code | `~/.claude/skills-managed/`  | `~/.claude/skills/<skill>/`        |
| Codex       | `~/.codex/skills-managed/`   | `~/.codex/skills/<skill>/`         |

Key points:

- **The managed clone and its links are owned by the sync.** Each sync
  hard-resets the clone to match the repo and re-links — any local edits to a
  managed skill are discarded. Treat managed skills as read-only.
- **Your personal skills are safe.** Real skill folders you created yourself are
  never modified or removed. If a managed skill's name collides with one of your
  personal skills, the sync **skips it and tells you** (it never overwrites
  yours).
- The two buttons are **independent** — click only the one for the tool you use.
- The repo is **private**, so a sync authenticates with a read-only **GitHub
  token**, stored securely on the machine (macOS Keychain; Windows: a protected
  per-user file) — never in `settings.json`.

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

### 3. Set up authentication

Pick **one** of the two options below.

---

#### Option A — Shared token (colleagues never touch GitHub) ★ recommended

Your colleagues stay completely oblivious to GitHub: no account, no invitation,
no token of their own. You create **one** read-only token and distribute it; they
paste it into BMad Manager once.

> **The read-only limit comes from the *token's scope*, not from a collaborator
> role.** A fine-grained token has its own `Contents: Read-only` permission that
> is independent of the account's repo access. So this works even on a
> **personal** repo — where collaborators can only be read **+ write** (there's
> no read-only collaborator role; those exist only on **organization** repos). A
> token you scope to read can still only read.

**Simplest — personal repo, no extra accounts, no invitations.** You, the repo
owner, just mint a narrowly-scoped token and share it:

1. **GitHub → Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token.**
2. **Resource owner:** your account (the one that owns the repo).
3. **Repository access → Only select repositories →** the skills repo.
4. **Permissions → Repository permissions → Contents → Read-only.** Nothing else.
5. **Expiration:** pick a window you're willing to rotate on (max ~1 year).
6. **Generate token** and copy it — GitHub shows it only once.
7. **Distribute** the token (and the repo URL) over a secure channel — a password
   manager / secrets vault, not chat.

That's it — the token can only read, even though your account can write to the
repo.

**Optional hardening — a dedicated service account.** If you'd rather the shared
token not be tied to your personal identity, create a separate "machine user"
account (e.g. `acme-bmad-bot`), give it access to the repo, and generate the
read-only token signed in as the bot:

- On a **personal** repo, add the bot as a collaborator (this grants it
  read **+ write** at the account level — unavoidable on personal repos), then
  scope the bot's token to `Contents: Read-only` as above. The distributed token
  is still read-only.
- On an **organization** repo, just give the bot (or a team) the **Read** role —
  genuine least privilege — then mint the read-only token.

Either way, send your team **Part 2 → "If your admin gave you a token
(Option A)"**.

**What you're trading off:** a shared token is a shared secret. There's **no
per-person revoke or audit** — to cut access you rotate the token for everyone.
Because it's **read-only and scoped to one repo**, the worst case if it leaks is
"someone could read your skills repo." When it expires or leaks, regenerate it and
redistribute; colleagues just paste the new value and Save.

---

#### Option B — Per-user tokens (per-person audit and revocation)

Each colleague authenticates as themselves. More steps for them, but you can
revoke or audit individuals.

> **This option needs an *organization-owned* repo.** Read-only collaborator/team
> roles only exist on organization repos. On a **personal** repo you can't grant
> read-only to people — collaborators get read **+ write** — so per-user *least
> privilege* isn't possible there. GitHub organizations are free; move the skills
> repo into one (repo → **Settings → Transfer ownership**) if you want this. (If
> you're staying on a personal repo, use **Option A** instead — its token scope
> gives you read-only without read-only roles.)

1. **Invite each teammate** to the repo with **Read** access: org repo →
   **Settings → Collaborators and teams** → **Add** → **Read** role.
2. Send them **Part 2 → "If you're using your own GitHub account (Option B)"**,
   where they accept the invite and create their own read-only token.

---

## Part 2 — Team member: sync the skills

Use the section that matches what your admin (the key user) set up.

### If your admin gave you a token (Option A)

You don't need a GitHub account and you don't visit github.com at all.

1. Open BMad Manager → **Settings** (the ⚙ icon).
2. Under **Global skills repository**:
   - **Skills repo URL:** the HTTPS URL your admin gave you, e.g.
     `https://github.com/your-org/bmad-skills`
   - **Branch:** leave as `main` unless told otherwise.
   - **GitHub token 🔒:** paste the token your admin gave you and click
     **Save token**. (macOS stores it in your Keychain; Windows in a protected
     per-user file — never in `settings.json`.)
3. Click **Done**, then jump to [Sync](#sync).

### If you're using your own GitHub account (Option B)

1. **Accept the invitation** from the key user (check your email or
   `https://github.com/notifications`). You can't sync a repo you can't read.
2. **Create a read-only token:**
   - **GitHub → Settings → Developer settings → Personal access tokens →
     Fine-grained tokens → Generate new token.**
   - **Resource owner:** the org/user that owns the skills repo.
   - **Repository access → Only select repositories →** the skills repo.
   - **Permissions → Repository permissions → Contents → Read-only.**
   - **Generate token** and copy it.
3. In BMad Manager → **Settings → Global skills repository**, enter the repo URL
   and branch, paste your token, **Save token**, **Done**.

### Sync

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
| `Set a GitHub token in Settings first.`  | No token stored — add one in Settings.                                       |
| `Set a skills repo URL in Settings first.` | The Skills repo URL field is empty.                                       |
| `Authentication failed` / `403`          | Token is wrong, expired, or lacks **Contents: Read** on this repo. Ask your admin for a fresh token (Option A) or regenerate your own (Option B). |
| `Repository not found` / `404`           | URL typo, or the token can't read the repo — confirm the URL with your admin. |
| `Remote branch <x> not found`            | The branch in Settings doesn't exist on the repo. Confirm it with the key user (usually `main`). |

Other notes:

- **Lost local edits to a managed skill?** Expected — managed skills are links
  to the hard-reset clone. Keep your own skills as separate folders (any name a
  managed skill doesn't use) and they're never touched.
- **A managed skill didn't appear?** If its name matches a personal skill you
  already have, the sync skips it (it won't overwrite yours) and says so in the
  output panel. Rename one side to resolve.
- **Changing the branch** in Settings and re-syncing switches the managed clone
  to that branch's latest commit.
- **Rotating a token:** paste the new value and **Save token** again (it
  overwrites the old one). **Clear** removes it entirely.
