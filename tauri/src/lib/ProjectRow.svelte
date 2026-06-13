<script lang="ts">
  import type { ProjectItem } from "./types";

  interface Props {
    project: ProjectItem;
    onClaude: () => void;
    onOpencode: () => void;
    onPi: () => void;
    onCodex: () => void;
    onOpenFolder: () => void;
    onDelete: () => void;
  }

  let { project, onClaude, onOpencode, onPi, onCodex, onOpenFolder, onDelete }: Props =
    $props();

  function relativeCreated(epoch: number | null): string {
    if (epoch === null) return "";
    const now = Date.now() / 1000;
    const diff = now - epoch;
    if (diff < 60) return "Created just now";
    if (diff < 3600) return `Created ${Math.round(diff / 60)} min ago`;
    if (diff < 86400) return `Created ${Math.round(diff / 3600)} h ago`;
    return `Created ${Math.round(diff / 86400)} d ago`;
  }
</script>

<li class="project-row">
  <span class="icon">📁</span>
  <div class="meta">
    <span class="name" title={project.path}>{project.name}</span>
    {#if project.createdAt !== null}
      <span class="created">{relativeCreated(project.createdAt)}</span>
    {/if}
  </div>
  <div class="actions">
    <!-- Agent buttons, ordered alphabetically by label. -->
    <button onclick={onClaude}>Claude Code</button>
    <button onclick={onCodex}>Codex</button>
    <button onclick={onOpencode}>opencode</button>
    <button onclick={onPi}>Pi</button>
    <button
      class="icon-btn"
      title="Open project folder"
      aria-label="Open project folder"
      onclick={onOpenFolder}
    >
      📂
    </button>
    <button
      class="danger"
      title="Move to Recycle Bin"
      aria-label="Delete project"
      onclick={onDelete}
    >
      🗑
    </button>
  </div>
</li>

<style>
  .project-row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    list-style: none;
  }

  .project-row:hover {
    background: rgba(127, 127, 127, 0.08);
  }

  .icon {
    font-size: 14px;
  }

  .meta {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .name {
    font-size: 13px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .created {
    font-size: 10px;
    color: rgba(127, 127, 127, 1);
  }

  .actions {
    display: flex;
    gap: 4px;
  }

  button {
    background: transparent;
    border: 1px solid rgba(127, 127, 127, 0.4);
    border-radius: 4px;
    padding: 2px 8px;
    font-size: 11px;
    color: inherit;
    cursor: pointer;
  }

  button:hover {
    background: rgba(127, 127, 127, 0.15);
  }

  button.danger {
    border-color: rgba(180, 30, 30, 0.4);
  }

  button.danger:hover {
    background: rgba(180, 30, 30, 0.12);
  }
</style>
