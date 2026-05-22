<script lang="ts">
  // Stage 1: placeholder UI shell. The three regions named in issue #25
  // (header with settings cogwheel, project list area, output panel) are
  // visibly laid out with hardcoded content. Stage 2 replaces the
  // placeholders with the real ContentView, ProjectRow, Settings, and
  // CommandOutput components ported from the Swift UI.

  let showOutput = $state(false);
  let showSettings = $state(false);
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

  <section class="project-list" data-testid="project-list">
    <div class="placeholder">
      <p>Stage 1 scaffold.</p>
      <p class="subtle">
        Stage 2 wires this region to the Rust <code>list_projects</code> command.
      </p>
    </div>
  </section>

  {#if showOutput}
    <section class="output-panel" data-testid="output-panel">
      <pre>(command output will stream here in Stage 2)</pre>
    </section>
  {/if}

  {#if showSettings}
    <div
      class="settings-modal"
      data-testid="settings-modal"
      role="dialog"
      aria-modal="true"
      aria-label="Settings"
    >
      <div class="settings-card">
        <h2>Settings</h2>
        <p class="subtle">
          Stage 2 replaces this placeholder with the full settings form
          (projects root, module source, init command, terminal, etc.).
        </p>
        <div class="settings-actions">
          <button onclick={() => (showSettings = false)}>Close</button>
        </div>
      </div>
    </div>
  {/if}
</main>

<style>
  .app {
    display: flex;
    flex-direction: column;
    height: 100vh;
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

  .project-list {
    flex: 1;
    padding: 16px;
    overflow: auto;
    min-height: 0;
  }

  .placeholder {
    text-align: center;
    margin-top: 64px;
  }

  .subtle {
    color: rgba(127, 127, 127, 1);
    font-size: 12px;
  }

  .output-panel {
    border-top: 1px solid rgba(127, 127, 127, 0.25);
    height: 200px;
    overflow: auto;
    padding: 8px 12px;
    background: rgba(127, 127, 127, 0.08);
    flex-shrink: 0;
  }

  .output-panel pre {
    margin: 0;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 12px;
  }

  .settings-modal {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.4);
    display: grid;
    place-items: center;
  }

  .settings-card {
    background: var(--card-bg, #ffffff);
    color: var(--card-fg, #1c1c1e);
    border-radius: 8px;
    padding: 20px;
    min-width: 360px;
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.25);
  }

  @media (prefers-color-scheme: dark) {
    .settings-card {
      background: #2c2c2e;
      color: #f5f5f7;
    }
  }

  .settings-card h2 {
    margin-top: 0;
  }

  .settings-actions {
    margin-top: 16px;
    display: flex;
    justify-content: flex-end;
  }
</style>
