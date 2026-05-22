<script lang="ts">
  import { listen, type UnlistenFn } from "@tauri-apps/api/event";
  import { onDestroy, onMount } from "svelte";
  import CommandOutput from "./lib/CommandOutput.svelte";
  import ProjectRow from "./lib/ProjectRow.svelte";
  import Settings from "./lib/Settings.svelte";
  import {
    createProject,
    deleteProject,
    listProjects,
    loadSettings,
    openInClaude,
    openInOpencode,
    saveSettings,
  } from "./lib/commands";
  import { projectSortOrderOptions, type AppSettings, type OutputEvent, type ProjectItem, type ProjectSortOrder } from "./lib/types";

  let settings: AppSettings | null = $state(null);
  let projects: ProjectItem[] = $state([]);
  let newProjectName = $state("");
  let isCreating = $state(false);
  let showSettings = $state(false);
  let showOutput = $state(false);
  let outputLines: string[] = $state([]);
  let lastExitCode: number | null = $state(null);
  let errorMessage: string | null = $state(null);

  let unlisten: UnlistenFn | null = null;

  onMount(async () => {
    try {
      settings = await loadSettings();
      await refresh();
      unlisten = await listen<OutputEvent>("project-create-output", (event) => {
        const payload = event.payload;
        if (payload.kind === "stdout" || payload.kind === "stderr") {
          outputLines = [...outputLines, payload.line];
        } else if (payload.kind === "exit") {
          lastExitCode = payload.code;
        }
      });
    } catch (err) {
      errorMessage = `Failed to load settings: ${err}`;
    }
  });

  onDestroy(() => {
    if (unlisten) unlisten();
  });

  async function refresh() {
    try {
      projects = await listProjects();
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
      await createProject(trimmed);
      newProjectName = "";
      await refresh();
    } catch (err) {
      errorMessage = `Create failed: ${err}`;
    } finally {
      isCreating = false;
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
            onDelete={() => onDelete(project)}
          />
        {/each}
      </ul>
    {/if}
  </section>

  {#if showOutput}
    <section class="output-panel" data-testid="output-panel">
      <CommandOutput
        lines={outputLines}
        isRunning={isCreating}
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

  .sort-row {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 4px 12px;
    flex-shrink: 0;
  }

  .sort-row .lbl {
    font-size: 11px;
    color: rgba(127, 127, 127, 1);
  }

  .sort-row select {
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
