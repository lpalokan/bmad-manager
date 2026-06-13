// Thin wrappers around Tauri's `invoke()` so component code never has to
// remember command names or argument-key casing.

import { invoke } from "@tauri-apps/api/core";
import type { AppSettings, BundledTooling, CompanyContext, ProjectItem } from "./types";

export const loadSettings = (): Promise<AppSettings> =>
  invoke<AppSettings>("load_settings");

export const getBundledTooling = (): Promise<BundledTooling> =>
  invoke<BundledTooling>("get_bundled_tooling");

export const saveSettings = (settings: AppSettings): Promise<void> =>
  invoke("save_settings", { settings });

export const defaultSettings = (): Promise<AppSettings> =>
  invoke<AppSettings>("default_settings");

export const listProjects = (): Promise<ProjectItem[]> =>
  invoke<ProjectItem[]>("list_projects");

export const listCompanyContexts = (): Promise<CompanyContext[]> =>
  invoke<CompanyContext[]>("list_company_contexts");

export const createProject = (
  name: string,
  context: CompanyContext | null = null,
): Promise<ProjectItem> => invoke<ProjectItem>("create_project", { name, context });

export const deleteProject = (path: string): Promise<void> =>
  invoke("delete_project", { path });

export const openInClaude = (projectPath: string): Promise<void> =>
  invoke("open_in_claude", { projectPath });

export const openInOpencode = (projectPath: string): Promise<void> =>
  invoke("open_in_opencode", { projectPath });

export const openInPi = (projectPath: string): Promise<void> =>
  invoke("open_in_pi", { projectPath });

export const openInCodex = (projectPath: string): Promise<void> =>
  invoke("open_in_codex", { projectPath });

export const openProjectFolder = (projectPath: string): Promise<void> =>
  invoke("open_project_folder", { projectPath });

export const detectCommandInPath = (command: string): Promise<string | null> =>
  invoke<string | null>("detect_command_in_path", { command });
