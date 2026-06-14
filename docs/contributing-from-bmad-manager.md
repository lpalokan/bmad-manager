# Contributing skills & contexts from BMad Manager

Once your company's skills/context repo exists (see
[skills-context-repo.md](skills-context-repo.md)), anyone with a contributor
token can propose **additions** to it without leaving BMad Manager. The app
opens a pull request; a reviewer merges it. You can never change existing repo
content this way — only add.

## One-time setup

1. Open **Settings → Global skills repository**.
2. Make sure **Skills repo URL** points at the shared repo.
3. In **Contributor token 🔒 (optional)**, paste a fine-grained PAT scoped to
   that repo with **Contents: Read and write** and **Pull requests: Read and
   write**. (See the repo guide for the exact recipe.) The token is stored in
   your OS credential store — Keychain on macOS, Credential Manager on Windows —
   never in `settings.json`.
4. Click **Test access**. You should see
   *“@you can push to org/repo — ready to contribute.”* If it says the token
   lacks write access, regenerate it with the two permissions above.

> No contributor token set? The app falls back to your read-only sync token, and
> a contribution attempt will fail with a permission error until you add a
> write-capable token.

## Contributing

1. On the main window, click **Contribute…** (next to the Sync buttons).
2. Tick the **personal skills** you want to share. Only your own skills are
   listed — skills synced from the repo are excluded.
3. Tick the **project contexts** you want to share. Each selected context gets
   an editable **folder name** (defaults to the project name) — this is the name
   it will have under `context/` in the repo.
4. Optionally set a **pull request title**.
5. Click **Open pull request**. The app:
   - stages your files under `skills/<name>/` and `context/<name>/`,
   - creates a branch and a single commit off the repo's default branch,
   - opens a PR, and
   - shows you the PR link.

A reviewer takes it from there.

## What gets sent

- **Skills:** every file in the skill folder (it must contain `SKILL.md`),
  preserving subfolders.
- **Contexts:** only the recognized files (`icp.md`, `positioning.md`,
  `brand-voice.md`, `kpis.md`, `tech-stack.md`); other files are skipped.
- Files over 1 MB are refused (skills/contexts are text — a large blob is almost
  certainly a mistake or a secret).

## Troubleshooting

| Message | Cause / fix |
| --- | --- |
| `Set a contributor GitHub token in Settings first.` | No write token (and no sync token) stored. Add one in Settings. |
| `… already exists in the repo — choose a different name` | A skill/context with that folder name is already in the repo. Additions only — rename it in the Contribute sheet. |
| `GitHub API error 403 …` | The token lacks **Contents** or **Pull requests** write, or you don't have access. Use **Test access** to check. |
| `GitHub API error 422 …` | Usually an open PR already covers this branch, or there's nothing to add. |
| `… is not a valid name for a repo folder.` | The target name has unsafe characters. Use letters, digits, `-`, `_`. |
