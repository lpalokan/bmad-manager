<script lang="ts">
  import { listen, type UnlistenFn } from "@tauri-apps/api/event";
  import { onDestroy, onMount } from "svelte";
  import CommandOutput from "./lib/CommandOutput.svelte";
  import Contribute from "./lib/Contribute.svelte";
  import ProjectRow from "./lib/ProjectRow.svelte";
  import Settings from "./lib/Settings.svelte";
  import {
    createProject,
    deleteProject,
    listCompanyContexts,
    listProjects,
    loadSettings,
    openInClaude,
    openInCodex,
    openInOpencode,
    openInPi,
    openProjectFolder,
    saveSettings,
    syncSkillsClaude,
    syncSkillsCodex,
    syncSkillsRepo,
  } from "./lib/commands";
  import { companyContextDisplayName, projectSortOrderOptions, type AppSettings, type CompanyContext, type OutputEvent, type ProjectItem, type ProjectSortOrder } from "./lib/types";

  let settings: AppSettings | null = $state(null);
  let projects: ProjectItem[] = $state([]);
  let contexts: CompanyContext[] = $state([]);
  // Directory path of the selected seeding source; "" = start from scratch.
  let selectedContextDir = $state("");
  let newProjectName = $state("");
  let isCreating = $state(false);
  let showSettings = $state(false);
  let showContribute = $state(false);
  let showOutput = $state(false);
  let outputLines: string[] = $state([]);
  let lastExitCode: number | null = $state(null);
  let errorMessage: string | null = $state(null);
  let isSyncing = $state(false);

  let unlisten: UnlistenFn | null = null;
  let unlistenSkills: UnlistenFn | null = null;

  function applyOutputEvent(payload: OutputEvent) {
    if (payload.kind === "stdout" || payload.kind === "stderr") {
      outputLines = [...outputLines, payload.line];
    } else if (payload.kind === "exit") {
      lastExitCode = payload.code;
    }
  }

  onMount(async () => {
    try {
      settings = await loadSettings();
      unlisten = await listen<OutputEvent>("project-create-output", (event) =>
        applyOutputEvent(event.payload),
      );
      // Skill syncs stream into the same output panel on their own channel.
      unlistenSkills = await listen<OutputEvent>("skills-sync-output", (event) =>
        applyOutputEvent(event.payload),
      );
      // Projects can change on disk while the app is backgrounded — created
      // in a terminal, deleted in Explorer, or left behind by a partially
      // failed create. Re-scan whenever the window regains focus so the list
      // reflects reality without forcing a restart.
      window.addEventListener("focus", refresh);
      // Show the local list immediately, then pull the shared skills repo
      // (skills + context/) and re-list so GitHub contexts appear.
      await refresh();
      await autoSync();
    } catch (err) {
      errorMessage = `Failed to load settings: ${err}`;
    }
  });

  // Auto-sync the shared skills repo, then re-list so the repo's context/
  // folder shows up. Listeners (above) capture the streamed git output.
  async function autoSync() {
    try {
      await syncSkillsRepo();
    } catch (err) {
      errorMessage = `Skill sync failed: ${err}`;
    }
    await refresh();
  }

  onDestroy(() => {
    if (unlisten) unlisten();
    if (unlistenSkills) unlistenSkills();
    window.removeEventListener("focus", refresh);
  });

  async function refresh() {
    try {
      projects = await listProjects();
      contexts = await listCompanyContexts();
      // The selected source project may have been deleted or its context
      // removed since the last scan — fall back to scratch rather than
      // importing from a stale snapshot.
      if (
        selectedContextDir &&
        !contexts.some((c) => c.directory === selectedContextDir)
      ) {
        selectedContextDir = "";
      }
    } catch (err) {
      errorMessage = `Failed to list projects: ${err}`;
    }
  }

  async function onCreate() {
    const trimmed = newProjectName.trim();
    if (!trimmed || isCreating) return;
    isCreating = true;
    showOutput = true;
    outputLines = [];
    lastExitCode = null;
    errorMessage = null;
    try {
      const context =
        contexts.find((c) => c.directory === selectedContextDir) ?? null;
      await createProject(trimmed, context);
      newProjectName = "";
      // Reset to scratch so the next creation doesn't silently inherit
      // the previous selection.
      selectedContextDir = "";
    } catch (err) {
      errorMessage = `Create failed: ${err}`;
    } finally {
      isCreating = false;
      // Refresh regardless of outcome: a create that fails partway (e.g. the
      // install succeeds but seeding the company context throws) still leaves
      // the project folder on disk, so it must show up in the list.
      await refresh();
    }
  }

  async function onSyncSkills(tool: "claude" | "codex") {
    if (isSyncing || isCreating) return;
    isSyncing = true;
    showOutput = true;
    outputLines = [];
    lastExitCode = null;
    errorMessage = null;
    try {
      await (tool === "claude" ? syncSkillsClaude() : syncSkillsCodex());
    } catch (err) {
      errorMessage = `Skill sync failed: ${err}`;
    } finally {
      isSyncing = false;
    }
  }

  async function onDelete(project: ProjectItem) {
    if (
      !confirm(`Move '${project.name}' to the Recycle Bin?`)
    ) {
      return;
    }
    try {
      await deleteProject(project.path);
      await refresh();
    } catch (err) {
      errorMessage = `Delete failed: ${err}`;
    }
  }

  async function onClaude(project: ProjectItem) {
    try {
      await openInClaude(project.path);
    } catch (err) {
      errorMessage = `Open in Claude failed: ${err}`;
    }
  }

  async function onOpencode(project: ProjectItem) {
    try {
      await openInOpencode(project.path);
    } catch (err) {
      errorMessage = `Open in opencode failed: ${err}`;
    }
  }

  async function onPi(project: ProjectItem) {
    try {
      await openInPi(project.path);
    } catch (err) {
      errorMessage = `Open in Pi failed: ${err}`;
    }
  }

  async function onCodex(project: ProjectItem) {
    try {
      await openInCodex(project.path);
    } catch (err) {
      errorMessage = `Open in Codex failed: ${err}`;
    }
  }

  async function onOpenFolder(project: ProjectItem) {
    try {
      await openProjectFolder(project.path);
    } catch (err) {
      errorMessage = `Open folder failed: ${err}`;
    }
  }

  async function changeSort(order: ProjectSortOrder) {
    if (!settings) return;
    settings.projectSortOrder = order;
    try {
      await saveSettings(settings);
      await refresh();
    } catch (err) {
      errorMessage = `Save failed: ${err}`;
    }
  }

  function dismissError() {
    errorMessage = null;
  }

  function settingsSaved(updated: AppSettings) {
    settings = updated;
    refresh();
  }

  const canCreate = $derived(
    !!settings && !isCreating && newProjectName.trim().length > 0,
  );
</script>

<main class="app">
  <header class="header" data-testid="header">
    <h1>BMad Manager</h1>
    <div class="header-actions">
      <button
        class="icon-btn"
        title="Refresh projects and sync the skills repo"
        aria-label="Refresh projects"
        data-testid="refresh-projects"
        onclick={autoSync}
      >
        ⟳
      </button>
      <button
        class="icon-btn"
        title={showOutput ? "Hide output" : "Show output"}
        aria-label="Toggle output panel"
        data-testid="toggle-output"
        onclick={() => (showOutput = !showOutput)}
      >
        {showOutput ? "▣" : "▢"}
      </button>
      <button
        class="icon-btn"
        title="Settings"
        aria-label="Open settings"
        data-testid="open-settings"
        onclick={() => (showSettings = true)}
      >
        ⚙
      </button>
    </div>
  </header>

  <section class="create-row">
    <input
      type="text"
      placeholder="New project name"
      bind:value={newProjectName}
      onkeydown={(e) => {
        if (e.key === "Enter" && canCreate) onCreate();
      }}
    />
    <button class="primary" disabled={!canCreate} onclick={onCreate}>
      {isCreating ? "Creating…" : "Create new project"}
    </button>
  </section>

  {#if contexts.length > 0}
    <section class="context-row" data-testid="context-row">
      <span class="lbl">Context</span>
      <select
        bind:value={selectedContextDir}
        title="Seed the new project's company context from an existing project"
        disabled={isCreating}
      >
        <option value="">Start from scratch</option>
        {#each contexts as context (context.directory)}
          <option value={context.directory}>
            {companyContextDisplayName(context)}
          </option>
        {/each}
      </select>
    </section>
  {/if}

  <section class="sort-row">
    <span class="lbl">Sort</span>
    <select
      value={settings?.projectSortOrder ?? "nameAscending"}
      onchange={(e) =>
        changeSort((e.target as HTMLSelectElement).value as ProjectSortOrder)}
      disabled={!settings}
    >
      {#each projectSortOrderOptions as opt (opt.value)}
        <option value={opt.value}>{opt.label}</option>
      {/each}
    </select>
  </section>

  {#if errorMessage}
    <div class="error-banner" role="alert">
      <span>{errorMessage}</span>
      <button onclick={dismissError} aria-label="Dismiss error">×</button>
    </div>
  {/if}

  <section class="project-list" data-testid="project-list">
    {#if projects.length === 0}
      <div class="empty">
        <p>No projects yet.</p>
        <p class="subtle">
          Type a name above and click <strong>Create new project</strong>.
        </p>
      </div>
    {:else}
      <ul>
        {#each projects as project (project.path)}
          <ProjectRow
            {project}
            onClaude={() => onClaude(project)}
            onOpencode={() => onOpencode(project)}
            onPi={() => onPi(project)}
            onCodex={() => onCodex(project)}
            onOpenFolder={() => onOpenFolder(project)}
            onDelete={() => onDelete(project)}
          />
        {/each}
      </ul>
    {/if}
  </section>

  <section class="skills-row" data-testid="skills-row">
    <span class="lbl">Skills</span>
    <button
      type="button"
      data-testid="sync-claude"
      disabled={isSyncing || isCreating || !settings?.skillsRepoUrl}
      onclick={() => onSyncSkills("claude")}
    >
      Sync to Claude Code
    </button>
    <button
      type="button"
      data-testid="sync-codex"
      disabled={isSyncing || isCreating || !settings?.skillsRepoUrl}
      onclick={() => onSyncSkills("codex")}
    >
      Sync to Codex
    </button>
    <button
      type="button"
      data-testid="contribute"
      disabled={!settings?.skillsRepoUrl}
      onclick={() => (showContribute = true)}
    >
      Contribute…
    </button>
    {#if !settings?.skillsRepoUrl}
      <span class="skills-hint">Set a skills repo URL in Settings ⚙ to enable.</span>
    {/if}
  </section>

  {#if showOutput}
    <section class="output-panel" data-testid="output-panel">
      <CommandOutput
        lines={outputLines}
        isRunning={isCreating || isSyncing}
        {lastExitCode}
      />
    </section>
  {/if}

  {#if showSettings && settings}
    <Settings
      {settings}
      onClose={() => (showSettings = false)}
      onSaved={settingsSaved}
    />
  {/if}

  {#if showContribute}
    <Contribute onClose={() => (showContribute = false)} />
  {/if}
</main>

<style>
  .app {
    display: flex;
    flex-direction: column;
    height: 100vh;
    min-height: 0;
  }

  .header {
    display: flex;
    align-items: center;
    padding: 8px 12px;
    border-bottom: 1px solid rgba(127, 127, 127, 0.25);
    flex-shrink: 0;
  }

  .header h1 {
    margin: 0;
    font-size: 14px;
    font-weight: 600;
    flex: 1;
  }

  .header-actions {
    display: flex;
    gap: 4px;
  }

  .icon-btn {
    background: none;
    border: 1px solid transparent;
    border-radius: 4px;
    cursor: pointer;
    font-size: 16px;
    padding: 4px 8px;
    color: inherit;
  }

  .icon-btn:hover {
    background: rgba(127, 127, 127, 0.15);
  }

  .create-row {
    display: flex;
    gap: 6px;
    padding: 8px 12px;
    border-bottom: 1px solid rgba(127, 127, 127, 0.12);
    flex-shrink: 0;
  }

  .create-row input {
    flex: 1;
    padding: 6px 8px;
    border: 1px solid rgba(127, 127, 127, 0.4);
    border-radius: 4px;
    font: inherit;
    background: transparent;
    color: inherit;
  }

  .primary {
    background: rgba(40, 100, 200, 0.85);
    color: white;
    border: 1px solid rgba(40, 100, 200, 0.85);
    border-radius: 4px;
    padding: 6px 12px;
    font: inherit;
    cursor: pointer;
  }

  .primary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .sort-row,
  .context-row,
  .skills-row {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 4px 12px;
    flex-shrink: 0;
  }

  .skills-row {
    border-top: 1px solid rgba(127, 127, 127, 0.12);
    padding: 8px 12px;
  }

  .skills-row button {
    padding: 4px 10px;
    border: 1px solid rgba(127, 127, 127, 0.4);
    border-radius: 4px;
    background: transparent;
    color: inherit;
    font: inherit;
    font-size: 12px;
    cursor: pointer;
  }

  .skills-row button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .skills-hint {
    font-size: 11px;
    color: rgba(127, 127, 127, 1);
  }

  .sort-row .lbl,
  .context-row .lbl,
  .skills-row .lbl {
    font-size: 11px;
    color: rgba(127, 127, 127, 1);
  }

  .sort-row select,
  .context-row select {
    padding: 2px 6px;
    border: 1px solid rgba(127, 127, 127, 0.4);
    border-radius: 4px;
    background: transparent;
    color: inherit;
    font: inherit;
    font-size: 11px;
  }

  .error-banner {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    background: rgba(180, 30, 30, 0.1);
    border-bottom: 1px solid rgba(180, 30, 30, 0.4);
    color: #b91d1d;
    font-size: 12px;
    flex-shrink: 0;
  }

  .error-banner span {
    flex: 1;
  }

  .error-banner button {
    background: none;
    border: none;
    color: inherit;
    font-size: 16px;
    cursor: pointer;
  }

  .project-list {
    flex: 1;
    overflow: auto;
    min-height: 0;
  }

  .project-list ul {
    margin: 0;
    padding: 0;
  }

  .empty {
    text-align: center;
    margin-top: 64px;
  }

  .subtle {
    color: rgba(127, 127, 127, 1);
    font-size: 12px;
  }

  .output-panel {
    height: 200px;
    flex-shrink: 0;
    display: flex;
    flex-direction: column;
    min-height: 0;
  }
</style>
