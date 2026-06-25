<script lang="ts">
  import { onMount } from "svelte";
  import { open } from "@tauri-apps/plugin-dialog";
  import {
    defaultSettings,
    detectCommandInPath,
    getBundledTooling,
    hasContributorToken,
    hasGithubToken,
    saveSettings,
    setContributorToken,
    setGithubToken,
    testRepoAccess,
  } from "./commands";
  import {
    moduleSourceOptions,
    terminalOptions,
    shellOptions,
    newSessionPlacementOptions,
    agentLaunchMethodOptions,
    type AppSettings,
    type BundledTooling,
  } from "./types";

  interface Props {
    settings: AppSettings;
    onClose: () => void;
    onSaved: (settings: AppSettings) => void;
  }

  let { settings, onClose, onSaved }: Props = $props();

  // Local working copy so the dialog can be cancelled without persisting.
  // svelte-ignore state_referenced_locally
  let draft: AppSettings = $state({ ...settings });
  let saving = $state(false);
  let saveError: string | null = $state(null);
  let bundled: BundledTooling | null = $state(null);
  let bundledError: string | null = $state(null);

  // GitHub skills-repo token. Stored in the OS credential store (Windows
  // Credential Manager; a protected per-user file on the dev/CI fallback) —
  // never in settings.json — so it's handled separately from `draft`. We only
  // learn whether one is stored, never its value.
  let githubToken = $state("");
  let tokenStored = $state(false);
  let tokenSaving = $state(false);
  let tokenError: string | null = $state(null);

  // Optional contributor (read-write) token, kept separate so syncing can stay
  // least-privilege. Falls back to the sync token when unset.
  let contributorToken = $state("");
  let contributorStored = $state(false);
  let contributorSaving = $state(false);
  let contributorError: string | null = $state(null);
  let testing = $state(false);
  let testResult: string | null = $state(null);
  let testOk = $state(false);

  onMount(async () => {
    try {
      bundled = await getBundledTooling();
    } catch (err) {
      bundledError = String(err);
    }
    try {
      tokenStored = await hasGithubToken();
    } catch {
      tokenStored = false;
    }
    try {
      contributorStored = await hasContributorToken();
    } catch {
      contributorStored = false;
    }
  });

  async function saveContributorToken() {
    contributorSaving = true;
    contributorError = null;
    try {
      await setContributorToken(contributorToken);
      contributorStored = contributorToken.trim().length > 0;
      contributorToken = "";
    } catch (err) {
      contributorError = String(err);
    } finally {
      contributorSaving = false;
    }
  }

  async function clearContributorToken() {
    contributorSaving = true;
    contributorError = null;
    try {
      await setContributorToken("");
      contributorStored = false;
      contributorToken = "";
    } catch (err) {
      contributorError = String(err);
    } finally {
      contributorSaving = false;
    }
  }

  async function runTestAccess() {
    testing = true;
    testResult = null;
    try {
      const report = await testRepoAccess();
      testOk = report.canPush;
      testResult = report.canPush
        ? `@${report.login} can push to ${report.repoFullName} — ready to contribute.`
        : `@${report.login} can read ${report.repoFullName} but the token lacks write access — contributions will fail.`;
    } catch (err) {
      testOk = false;
      testResult = String(err);
    } finally {
      testing = false;
    }
  }

  async function saveToken() {
    tokenSaving = true;
    tokenError = null;
    try {
      await setGithubToken(githubToken);
      tokenStored = githubToken.trim().length > 0;
      githubToken = "";
    } catch (err) {
      tokenError = String(err);
    } finally {
      tokenSaving = false;
    }
  }

  async function clearToken() {
    tokenSaving = true;
    tokenError = null;
    try {
      await setGithubToken("");
      tokenStored = false;
      githubToken = "";
    } catch (err) {
      tokenError = String(err);
    } finally {
      tokenSaving = false;
    }
  }

  // Per-agent PATH-detection results. `null` = unknown / pending,
  // a string = resolved absolute path, `false` = checked and not found.
  type Detection = string | false | null;
  let detections: Record<"claude" | "opencode" | "pi" | "codex", Detection> = $state({
    claude: null,
    opencode: null,
    pi: null,
    codex: null,
  });

  async function detect(which: "claude" | "opencode" | "pi" | "codex", command: string) {
    detections[which] = null;
    const trimmed = command.trim();
    if (!trimmed) {
      detections[which] = false;
      return;
    }
    try {
      const found = await detectCommandInPath(trimmed);
      detections[which] = found ?? false;
    } catch {
      detections[which] = false;
    }
  }

  $effect(() => {
    detect("claude", draft.claudeCommand);
  });
  $effect(() => {
    detect("opencode", draft.opencodeCommand);
  });
  $effect(() => {
    detect("pi", draft.piCommand);
  });
  $effect(() => {
    detect("codex", draft.codexCommand);
  });

  async function browseForAgent(
    which: "claude" | "opencode" | "pi" | "codex",
    label: string,
  ) {
    const picked = await open({
      multiple: false,
      title: `Choose ${label} executable`,
    });
    if (typeof picked === "string") {
      if (which === "claude") draft.claudeCommand = picked;
      else if (which === "opencode") draft.opencodeCommand = picked;
      else if (which === "pi") draft.piCommand = picked;
      else draft.codexCommand = picked;
    }
  }

  async function chooseFolder() {
    const picked = await open({
      directory: true,
      multiple: false,
      title: "Choose projects folder",
    });
    if (typeof picked === "string") {
      draft.projectsRoot = picked;
    }
  }

  async function chooseZip() {
    const picked = await open({
      multiple: false,
      filters: [{ name: "Zip", extensions: ["zip"] }],
      title: "Choose marketing growth module",
    });
    if (typeof picked === "string") {
      draft.moduleZipPath = picked;
    }
  }

  async function done() {
    saving = true;
    saveError = null;
    try {
      await saveSettings(draft);
      onSaved(draft);
      onClose();
    } catch (err) {
      saveError = String(err);
    } finally {
      saving = false;
    }
  }

  async function resetToDefaults() {
    if (
      !confirm(
        "Reset all settings to defaults? Your projects folder and any customised commands will be wiped.",
      )
    ) {
      return;
    }
    // The defaults() helper lives in Rust; load them via the IPC rather than
    // duplicating them here. We populate the draft (not the persisted file)
    // so the user can review the restored configuration and Save with "Done"
    // — or cancel out without having clobbered anything.
    saveError = null;
    try {
      draft = await defaultSettings();
    } catch (err) {
      saveError = String(err);
    }
  }
</script>

<div
  class="settings-modal"
  role="dialog"
  aria-modal="true"
  aria-label="Settings"
  data-testid="settings-modal"
>
  <div class="settings-card">
    <h2>Settings</h2>

    <section>
      <label class="lbl" for="projects-root">Projects root folder</label>
      <div class="row">
        <input id="projects-root" type="text" bind:value={draft.projectsRoot} />
        <button onclick={chooseFolder} type="button">Choose…</button>
      </div>
    </section>

    <section>
      <label class="lbl" for="source-kind">Marketing growth module source</label>
      <div class="segmented" role="group" id="source-kind">
        {#each moduleSourceOptions as opt (opt.value)}
          <button
            type="button"
            class:active={draft.moduleSourceKind === opt.value}
            onclick={() => (draft.moduleSourceKind = opt.value)}
          >
            {opt.label}
          </button>
        {/each}
      </div>

      {#if draft.moduleSourceKind === "gitRepo"}
        <input
          type="text"
          placeholder="GitHub repo URL"
          bind:value={draft.moduleRepoUrl}
        />
        <input
          type="text"
          placeholder="Branch, tag, or SHA (blank = default branch)"
          bind:value={draft.moduleRepoRef}
        />
        <p class="hint">
          Requires git on PATH. Stage 3 bundles PortableGit so end users
          don't need to install it.
        </p>
      {:else}
        <div class="row">
          <input
            type="text"
            placeholder="Path to .zip"
            bind:value={draft.moduleZipPath}
          />
          <button onclick={chooseZip} type="button">Choose…</button>
        </div>
        <p class="hint">
          GitHub "Download ZIP" archives are unwrapped automatically.
        </p>
      {/if}
    </section>

    <section>
      <label class="lbl" for="init-command">Init command</label>
      <textarea
        id="init-command"
        rows="4"
        bind:value={draft.initCommand}
      ></textarea>
      <p class="hint">
        Placeholders: {"{PROJECT_PATH}"}, {"{MODULE_PATH}"}, {"{PROJECT_NAME}"}.
        Single-quoted paths are rewritten to double-quoted ones for cmd.exe.
      </p>
    </section>

    <section>
      <label class="lbl" for="terminal-kind">Terminal</label>
      <div class="segmented" role="group" id="terminal-kind">
        {#each terminalOptions as opt (opt.value)}
          <button
            type="button"
            class:active={draft.terminalKind === opt.value}
            onclick={() => (draft.terminalKind = opt.value)}
          >
            {opt.label}
          </button>
        {/each}
      </div>
    </section>

    <section>
      <label class="lbl" for="shell-kind">Shell</label>
      <div class="segmented" role="group" id="shell-kind">
        {#each shellOptions as opt (opt.value)}
          <button
            type="button"
            class:active={draft.shellKind === opt.value}
            onclick={() => (draft.shellKind = opt.value)}
          >
            {opt.label}
          </button>
        {/each}
      </div>
      <p class="hint">
        What runs inside a launched session. PowerShell 7 must be installed
        separately to use it.
      </p>
    </section>

    {#if draft.terminalKind === "windowsTerminal"}
      <section>
        <label class="lbl" for="new-session-placement">
          Open new sessions in
        </label>
        <div class="segmented" role="group" id="new-session-placement">
          {#each newSessionPlacementOptions as opt (opt.value)}
            <button
              type="button"
              class:active={draft.newSessionPlacement === opt.value}
              onclick={() => (draft.newSessionPlacement = opt.value)}
            >
              {opt.label}
            </button>
          {/each}
        </div>
        <p class="hint">
          Tabs open in one dedicated Windows Terminal window. Requires Windows
          Terminal.
        </p>
      </section>
    {/if}

    <section class="agents">
      <div>
        <label class="lbl" for="claude-cmd">Claude Code command</label>
        <div class="row">
          <input id="claude-cmd" type="text" bind:value={draft.claudeCommand} />
          <button
            type="button"
            onclick={() => browseForAgent("claude", "Claude Code")}
          >
            Browse…
          </button>
        </div>
        {#if detections.claude === null}
          <p class="hint">Checking PATH…</p>
        {:else if detections.claude === false}
          <p class="hint not-found">
            Not found on PATH. Use <strong>Browse…</strong> to point at the binary.
          </p>
        {:else}
          <p class="hint detected">Detected at <code>{detections.claude}</code></p>
        {/if}
        <label class="lbl sub" for="claude-launch">Launch as</label>
        <div class="segmented" role="group" id="claude-launch">
          {#each agentLaunchMethodOptions as opt (opt.value)}
            <button
              type="button"
              class:active={draft.claudeLaunchMethod === opt.value}
              onclick={() => (draft.claudeLaunchMethod = opt.value)}
            >
              {opt.label}
            </button>
          {/each}
        </div>
      </div>
      <div>
        <label class="lbl" for="opencode-cmd">opencode command</label>
        <div class="row">
          <input id="opencode-cmd" type="text" bind:value={draft.opencodeCommand} />
          <button
            type="button"
            onclick={() => browseForAgent("opencode", "opencode")}
          >
            Browse…
          </button>
        </div>
        {#if detections.opencode === null}
          <p class="hint">Checking PATH…</p>
        {:else if detections.opencode === false}
          <p class="hint not-found">
            Not found on PATH. Use <strong>Browse…</strong> to point at the binary.
          </p>
        {:else}
          <p class="hint detected">Detected at <code>{detections.opencode}</code></p>
        {/if}
      </div>
      <div>
        <label class="lbl" for="pi-cmd">Pi command</label>
        <div class="row">
          <input id="pi-cmd" type="text" bind:value={draft.piCommand} />
          <button type="button" onclick={() => browseForAgent("pi", "Pi")}>
            Browse…
          </button>
        </div>
        {#if detections.pi === null}
          <p class="hint">Checking PATH…</p>
        {:else if detections.pi === false}
          <p class="hint not-found">
            Not found on PATH. Use <strong>Browse…</strong> to point at the binary.
          </p>
        {:else}
          <p class="hint detected">Detected at <code>{detections.pi}</code></p>
        {/if}
      </div>
      <div>
        <label class="lbl" for="codex-cmd">Codex command</label>
        <div class="row">
          <input id="codex-cmd" type="text" bind:value={draft.codexCommand} />
          <button type="button" onclick={() => browseForAgent("codex", "Codex")}>
            Browse…
          </button>
        </div>
        {#if detections.codex === null}
          <p class="hint">Checking PATH…</p>
        {:else if detections.codex === false}
          <p class="hint not-found">
            Not found on PATH. Use <strong>Browse…</strong> to point at the binary.
          </p>
        {:else}
          <p class="hint detected">Detected at <code>{detections.codex}</code></p>
        {/if}
        <label class="lbl sub" for="codex-launch">Launch as</label>
        <div class="segmented" role="group" id="codex-launch">
          {#each agentLaunchMethodOptions as opt (opt.value)}
            <button
              type="button"
              class:active={draft.codexLaunchMethod === opt.value}
              onclick={() => (draft.codexLaunchMethod = opt.value)}
            >
              {opt.label}
            </button>
          {/each}
        </div>
        <p class="hint">
          "Desktop app" opens the Codex GUI on the project; "CLI in terminal"
          runs the command above. "Auto" prefers the app when it's installed.
        </p>
      </div>
    </section>

    <section data-testid="skills-settings">
      <span class="lbl">Global skills repository</span>
      <p class="hint">
        Sync a private GitHub skills repo into your global Claude Code / Codex
        skills folders from the main window. The token is stored in your OS
        credential store, never in settings.json.
      </p>
      <label class="lbl sub" for="skills-repo-url">Skills repo URL</label>
      <input
        id="skills-repo-url"
        type="text"
        placeholder="https://github.com/your-org/bmad-skills"
        bind:value={draft.skillsRepoUrl}
      />
      <label class="lbl sub" for="skills-repo-branch">Branch</label>
      <input
        id="skills-repo-branch"
        type="text"
        placeholder="main"
        bind:value={draft.skillsRepoBranch}
      />
      <label class="lbl sub" for="skills-token">
        GitHub token 🔒
      </label>
      <div class="row">
        <input
          id="skills-token"
          type="password"
          autocomplete="off"
          placeholder={tokenStored ? "•••••••• (stored)" : "Fine-grained read-only PAT"}
          bind:value={githubToken}
        />
        <button
          type="button"
          disabled={tokenSaving || githubToken.trim().length === 0}
          onclick={saveToken}
        >
          {tokenSaving ? "Saving…" : "Save token"}
        </button>
        {#if tokenStored}
          <button type="button" disabled={tokenSaving} onclick={clearToken}>
            Clear
          </button>
        {/if}
      </div>
      {#if tokenError}
        <p class="hint not-found">Token error: {tokenError}</p>
      {:else if tokenStored}
        <p class="hint detected">A token is stored for this machine.</p>
      {:else}
        <p class="hint">
          Create a fine-grained PAT with read-only Contents access to the
          skills repo, then paste it here.
        </p>
      {/if}

      <label class="lbl sub" for="contributor-token">
        Contributor token 🔒 (optional)
      </label>
      <div class="row">
        <input
          id="contributor-token"
          type="password"
          autocomplete="off"
          placeholder={contributorStored ? "•••••••• (stored)" : "Fine-grained read-write PAT"}
          bind:value={contributorToken}
        />
        <button
          type="button"
          disabled={contributorSaving || contributorToken.trim().length === 0}
          onclick={saveContributorToken}
        >
          {contributorSaving ? "Saving…" : "Save token"}
        </button>
        {#if contributorStored}
          <button
            type="button"
            disabled={contributorSaving}
            onclick={clearContributorToken}
          >
            Clear
          </button>
        {/if}
        <button
          type="button"
          data-testid="test-repo-access"
          disabled={testing || !draft.skillsRepoUrl}
          onclick={runTestAccess}
        >
          {testing ? "Testing…" : "Test access"}
        </button>
      </div>
      {#if contributorError}
        <p class="hint not-found">Token error: {contributorError}</p>
      {:else if testResult}
        <p class="hint {testOk ? 'detected' : 'not-found'}">{testResult}</p>
      {:else}
        <p class="hint">
          To contribute skills/contexts as pull requests, add a fine-grained
          PAT with <strong>Contents: Read and write</strong> and
          <strong>Pull requests: Read and write</strong> scoped to the skills
          repo. Leave empty to reuse the read-only token above (contributions
          will then fail until a write token is set).
        </p>
      {/if}
    </section>

    <section data-testid="bundled-tooling">
      <span class="lbl">Bundled tooling</span>
      <div class="bundled">
        {#if bundledError}
          <p class="hint">Couldn't read bundled versions: {bundledError}</p>
        {:else if bundled}
          <dl>
            <dt>Node</dt>
            <dd>{bundled.nodeVersion ?? "not bundled (uses system node)"}</dd>
            <dt>Git</dt>
            <dd>{bundled.gitVersion ?? "not bundled (uses system git)"}</dd>
          </dl>
        {:else}
          <p class="hint">Reading versions…</p>
        {/if}
        <p class="hint">
          Read-only. These ship inside the installer so end users don't
          need to install Node or Git separately.
        </p>
      </div>
    </section>

    <section data-testid="bundled-tooling">
      <span class="lbl">Bundled tooling</span>
      <div class="bundled">
        {#if bundledError}
          <p class="hint">Couldn't read bundled versions: {bundledError}</p>
        {:else if bundled}
          <dl>
            <dt>Node</dt>
            <dd>{bundled.nodeVersion ?? "not bundled (uses system node)"}</dd>
            <dt>Git</dt>
            <dd>{bundled.gitVersion ?? "not bundled (uses system git)"}</dd>
          </dl>
        {:else}
          <p class="hint">Reading versions…</p>
        {/if}
        <p class="hint">
          Read-only. These ship inside the installer so end users don't
          need to install Node or Git separately.
        </p>
      </div>
    </section>

    {#if saveError}
      <p class="error">Failed to save: {saveError}</p>
    {/if}

    <footer class="actions">
      <button type="button" class="reset" onclick={resetToDefaults}>
        Reset to defaults
      </button>
      <span class="spacer"></span>
      <button type="button" onclick={onClose} disabled={saving}>Cancel</button>
      <button type="button" class="primary" onclick={done} disabled={saving}>
        {saving ? "Saving…" : "Done"}
      </button>
    </footer>
  </div>
</div>

<style>
  .settings-modal {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.4);
    display: grid;
    place-items: center;
    z-index: 10;
  }

  .settings-card {
    background: var(--card-bg, #ffffff);
    color: var(--card-fg, #1c1c1e);
    border-radius: 8px;
    padding: 20px;
    width: min(640px, 90vw);
    max-height: 90vh;
    overflow: auto;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.25);
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  @media (prefers-color-scheme: dark) {
    .settings-card {
      background: #2c2c2e;
      color: #f5f5f7;
    }
  }

  h2 {
    margin: 0;
    font-size: 16px;
  }

  section {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .lbl {
    font-size: 12px;
    font-weight: 600;
  }

  .lbl.sub {
    font-weight: 500;
    margin-top: 4px;
    opacity: 0.85;
  }

  .row {
    display: flex;
    gap: 6px;
  }

  input,
  textarea {
    flex: 1;
    padding: 6px 8px;
    border: 1px solid rgba(127, 127, 127, 0.4);
    border-radius: 4px;
    font: inherit;
    background: transparent;
    color: inherit;
  }

  textarea {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 12px;
    resize: vertical;
  }

  button {
    padding: 6px 12px;
    border: 1px solid rgba(127, 127, 127, 0.4);
    border-radius: 4px;
    background: transparent;
    color: inherit;
    cursor: pointer;
    font: inherit;
  }

  button:hover:not(:disabled) {
    background: rgba(127, 127, 127, 0.15);
  }

  button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .segmented {
    display: flex;
    border: 1px solid rgba(127, 127, 127, 0.4);
    border-radius: 4px;
    overflow: hidden;
    width: fit-content;
  }

  .segmented button {
    border: none;
    border-radius: 0;
    padding: 4px 12px;
    font-size: 12px;
  }

  .segmented button.active {
    background: rgba(127, 127, 127, 0.25);
    font-weight: 600;
  }

  .hint {
    margin: 0;
    font-size: 11px;
    color: rgba(127, 127, 127, 1);
  }

  .agents {
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .agents > div {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .hint.detected {
    color: rgb(40, 130, 60);
  }

  .hint.not-found {
    color: #b91d1d;
  }

  .hint code {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 11px;
  }

  .error {
    margin: 0;
    color: #b91d1d;
    font-size: 12px;
  }

  .actions {
    display: flex;
    align-items: center;
    gap: 8px;
    border-top: 1px solid rgba(127, 127, 127, 0.25);
    padding-top: 12px;
  }

  .spacer {
    flex: 1;
  }

  .primary {
    background: rgba(40, 100, 200, 0.85);
    color: white;
    border-color: rgba(40, 100, 200, 0.85);
  }

  .primary:hover:not(:disabled) {
    background: rgba(40, 100, 200, 1);
  }

  .reset {
    color: #b91d1d;
    border-color: rgba(180, 30, 30, 0.4);
  }

  .bundled dl {
    margin: 0;
    display: grid;
    grid-template-columns: max-content 1fr;
    gap: 2px 12px;
    font-size: 12px;
  }

  .bundled dt {
    font-weight: 600;
  }

  .bundled dd {
    margin: 0;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  }
</style>
