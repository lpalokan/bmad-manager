<script lang="ts">
  import { onMount } from "svelte";
  import {
    companyContextDisplayName,
    type CompanyContext,
    type ContributableSkill,
    type ContributionRequest,
  } from "./types";
  import { listContributableItems, submitContribution } from "./commands";

  interface Props {
    onClose: () => void;
  }

  let { onClose }: Props = $props();

  let loading = $state(true);
  let loadError: string | null = $state(null);
  let skills: ContributableSkill[] = $state([]);
  let contexts: CompanyContext[] = $state([]);

  // Selection state, keyed by directory (unique per item).
  let selectedSkills = $state<Record<string, boolean>>({});
  let selectedContexts = $state<Record<string, boolean>>({});
  // Editable target folder name per context (defaults to the project name).
  let contextNames = $state<Record<string, string>>({});

  let title = $state("");
  let submitting = $state(false);
  let submitError: string | null = $state(null);
  let prUrl: string | null = $state(null);

  onMount(async () => {
    try {
      const items = await listContributableItems();
      skills = items.skills;
      contexts = items.contexts;
      for (const c of contexts) contextNames[c.directory] = c.projectName;
    } catch (err) {
      loadError = String(err);
    } finally {
      loading = false;
    }
  });

  const chosenSkills = $derived(skills.filter((s) => selectedSkills[s.directory]));
  const chosenContexts = $derived(
    contexts.filter((c) => selectedContexts[c.directory]),
  );
  const canSubmit = $derived(
    !submitting && chosenSkills.length + chosenContexts.length > 0,
  );

  async function submit() {
    if (!canSubmit) return;
    submitting = true;
    submitError = null;
    prUrl = null;
    try {
      const request: ContributionRequest = {
        skills: chosenSkills.map((s) => ({ name: s.name, directory: s.directory })),
        contexts: chosenContexts.map((c) => ({
          targetName: (contextNames[c.directory] ?? c.projectName).trim(),
          directory: c.directory,
          files: c.files,
        })),
        title: title.trim() || null,
      };
      const result = await submitContribution(request);
      prUrl = result.url;
    } catch (err) {
      submitError = String(err);
    } finally {
      submitting = false;
    }
  }
</script>

<div
  class="contribute-modal"
  role="dialog"
  aria-modal="true"
  aria-label="Contribute"
  data-testid="contribute-modal"
>
  <div class="contribute-card">
    <h2>Contribute to the shared repo</h2>
    <p class="hint">
      Propose your own skills and project contexts as a pull request. Nothing is
      changed in the repo directly — a reviewer merges your additions.
    </p>

    {#if loading}
      <p class="hint">Loading your skills and contexts…</p>
    {:else if loadError}
      <p class="hint not-found">Failed to load: {loadError}</p>
    {:else if prUrl}
      <p class="hint detected">Pull request opened.</p>
      <div class="row">
        <a href={prUrl} target="_blank" rel="noreferrer">{prUrl}</a>
      </div>
    {:else}
      <section>
        <span class="lbl">Personal skills</span>
        {#if skills.length === 0}
          <p class="hint">No personal skills found in your skills folders.</p>
        {:else}
          {#each skills as skill (skill.directory)}
            <label class="check">
              <input
                type="checkbox"
                bind:checked={selectedSkills[skill.directory]}
              />
              <span>{skill.name}</span>
              <span class="muted">({skill.tool})</span>
            </label>
          {/each}
        {/if}
      </section>

      <section>
        <span class="lbl">Project contexts</span>
        {#if contexts.length === 0}
          <p class="hint">No project contexts found.</p>
        {:else}
          {#each contexts as context (context.directory)}
            <div class="ctx-row">
              <label class="check">
                <input
                  type="checkbox"
                  bind:checked={selectedContexts[context.directory]}
                />
                <span>{companyContextDisplayName(context)}</span>
              </label>
              {#if selectedContexts[context.directory]}
                <input
                  class="name-input"
                  type="text"
                  aria-label="Target folder name"
                  bind:value={contextNames[context.directory]}
                />
              {/if}
            </div>
          {/each}
        {/if}
      </section>

      <section>
        <label class="lbl sub" for="pr-title">Pull request title (optional)</label>
        <input
          id="pr-title"
          type="text"
          placeholder="Add skill / context"
          bind:value={title}
        />
      </section>

      {#if submitError}
        <p class="hint not-found">{submitError}</p>
      {/if}
    {/if}

    <div class="actions">
      <button type="button" onclick={onClose}>{prUrl ? "Close" : "Cancel"}</button>
      {#if !prUrl}
        <button
          type="button"
          class="primary"
          data-testid="submit-contribution"
          disabled={!canSubmit || loading || !!loadError}
          onclick={submit}
        >
          {submitting ? "Opening PR…" : "Open pull request"}
        </button>
      {/if}
    </div>
  </div>
</div>

<style>
  .contribute-modal {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.4);
    display: grid;
    place-items: center;
    z-index: 10;
  }

  .contribute-card {
    background: var(--card-bg, #ffffff);
    color: var(--card-fg, #1c1c1e);
    border-radius: 8px;
    padding: 20px;
    width: min(560px, 90vw);
    max-height: 90vh;
    overflow: auto;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.25);
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  @media (prefers-color-scheme: dark) {
    .contribute-card {
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
    font-weight: 600;
    font-size: 13px;
  }

  .lbl.sub {
    font-weight: 500;
  }

  .hint {
    font-size: 12px;
    color: rgba(127, 127, 127, 1);
    margin: 0;
  }

  .hint.not-found {
    color: #b91d1d;
  }

  .hint.detected {
    color: #1a7f37;
  }

  .check {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 13px;
  }

  .muted {
    color: rgba(127, 127, 127, 1);
    font-size: 11px;
  }

  .ctx-row {
    display: flex;
    align-items: center;
    gap: 8px;
    justify-content: space-between;
  }

  input[type="text"] {
    padding: 6px 8px;
    border: 1px solid rgba(127, 127, 127, 0.4);
    border-radius: 4px;
    font: inherit;
    background: transparent;
    color: inherit;
  }

  .name-input {
    width: 180px;
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }

  button {
    padding: 6px 12px;
    border: 1px solid rgba(127, 127, 127, 0.4);
    border-radius: 4px;
    background: transparent;
    color: inherit;
    font: inherit;
    cursor: pointer;
  }

  button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .primary {
    background: rgba(40, 100, 200, 0.85);
    color: white;
    border-color: rgba(40, 100, 200, 0.85);
  }
</style>
