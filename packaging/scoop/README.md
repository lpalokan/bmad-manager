# Scoop packaging

`bmad-manager.json` is the reference copy of the [Scoop](https://scoop.sh) manifest
for the Windows build. The authoritative copy lives in the separate **bucket repo**
`lpalokan/scoop-bucket` at `bucket/bmad-manager.json`; the `release` workflow
patches `version`, `url`, and `hash` there on every published release (mirroring the
Homebrew cask update).

## How the pieces fit

- `tauri-windows.yml` builds a portable zip (`bmad-manager-windows-x64-portable.zip`)
  directly from the compiled `bmad-manager.exe` plus the bundled resource dirs
  (`pnpm tauri build --no-bundle` — no NSIS installer is produced, since Scoop is the
  Windows distribution channel), then attaches it to the GitHub Release.
- `release.yml`'s `scoop-publish` job downloads that zip, computes its SHA256, and
  updates the manifest in the bucket repo. The job is guarded on the
  `SCOOP_BUCKET_TOKEN` secret, so releases still succeed before it is configured.

## Why no `persist`

All user-writable state lives outside the install dir — `%LOCALAPPDATA%\bmad-manager`
(npm cache) and Windows Credential Manager (skills token) — so `scoop update`
swaps program files and preserves user data automatically. The bundled
`node-portable` / `portable-git` / `npm-cache` are read-only program files that
should be replaced on upgrade, so they must not be persisted.

## One-time setup (bucket repo + token)

See the PR description / project docs. In short: create `lpalokan/scoop-bucket`,
seed it with this manifest under `bucket/`, and add a `SCOOP_BUCKET_TOKEN` secret
(a PAT with write access to the bucket repo) to the `bmad-manager` repo.

## User commands

```
scoop bucket add lpalokan https://github.com/lpalokan/scoop-bucket
scoop install bmad-manager
scoop update bmad-manager
```
