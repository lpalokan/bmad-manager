import { Given, Then } from "@cucumber/cucumber";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import assert from "node:assert/strict";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const projectRoot = resolve(__dirname, "..", "..");

Given("the Svelte project has a vite config", function () {
  assert.ok(
    existsSync(resolve(projectRoot, "vite.config.ts")),
    "expected tauri/vite.config.ts to exist",
  );
});

Then("the BDD harness runs", function () {
  // Reaching this step proves cucumber discovered the feature file,
  // matched the step bindings, and executed them.
});
