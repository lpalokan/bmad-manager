Feature: Stage 1 scaffold smoke

  Verifies the cucumber-js harness can discover features, load step
  definitions, and execute them. Stage 2 expands this with
  Playwright-driven scenarios that drive the real Tauri webview.

  Scenario: BDD harness runs
    Given the Svelte project has a vite config
    Then the BDD harness runs
