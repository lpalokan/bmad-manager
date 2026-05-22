import { setWorldConstructor, World } from "@cucumber/cucumber";

// Stage 1 keeps the World empty; Stage 2 hangs the Playwright browser
// context, the Tauri dev process handle, and shared test fixtures off it.
class TauriUIWorld extends World {}

setWorldConstructor(TauriUIWorld);
