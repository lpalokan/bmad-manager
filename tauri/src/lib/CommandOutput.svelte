<script lang="ts">
  import type { OutputEvent } from "./types";

  interface Props {
    lines: string[];
    isRunning: boolean;
    lastExitCode: number | null;
  }

  let { lines, isRunning, lastExitCode }: Props = $props();

  let scrollEl: HTMLDivElement | undefined = $state();

  $effect(() => {
    // Auto-scroll to bottom whenever new content arrives.
    void lines.length;
    if (scrollEl) {
      scrollEl.scrollTop = scrollEl.scrollHeight;
    }
  });

  export function append(event: OutputEvent) {
    if (event.kind === "stdout" || event.kind === "stderr") {
      // No-op: parent owns the lines array. Kept as a hook in case a
      // future refactor moves event handling here.
    }
  }
</script>

<div class="command-output">
  <header class="bar">
    <span class="label">Output</span>
    <span class="status">
      {#if isRunning}
        <span class="running">Running…</span>
      {:else if lastExitCode !== null}
        <span class="exit" class:ok={lastExitCode === 0} class:err={lastExitCode !== 0}>
          Exit: {lastExitCode}
        </span>
      {/if}
    </span>
  </header>
  <div class="scroll" bind:this={scrollEl}>
    {#if lines.length === 0}
      <pre class="empty">(no output yet)</pre>
    {:else}
      <pre>{lines.join("\n")}</pre>
    {/if}
  </div>
</div>

<style>
  .command-output {
    display: flex;
    flex-direction: column;
    height: 100%;
    background: rgba(127, 127, 127, 0.08);
    border-top: 1px solid rgba(127, 127, 127, 0.25);
    min-height: 0;
  }

  .bar {
    display: flex;
    align-items: center;
    padding: 4px 12px;
    font-size: 11px;
    color: rgba(127, 127, 127, 1);
    flex-shrink: 0;
  }

  .label {
    flex: 1;
  }

  .running {
    font-style: italic;
  }

  .exit {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  }

  .exit.ok {
    color: #0a7d3a;
  }

  .exit.err {
    color: #b91d1d;
  }

  .scroll {
    overflow: auto;
    flex: 1;
    padding: 8px 12px;
    min-height: 0;
  }

  pre {
    margin: 0;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 12px;
    white-space: pre-wrap;
    word-break: break-all;
  }

  pre.empty {
    color: rgba(127, 127, 127, 1);
    font-style: italic;
  }
</style>
