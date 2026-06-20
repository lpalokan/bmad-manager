// Thin wrappers around Tauri's `invoke()` so component code never has to
// remember command names or argument-key casing.

import { invoke } from "@tauri-apps/api/core";
import type {
  AppSettings,
  BundledTooling,
  CompanyContext,
  ContributableItems,
  ContributionRequest,
  ContributionResult,
  InitTargetInfo,
  ProjectItem,
  RepoAccessReport,
} from "./types";

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

// `targetPath`, when given, is an existing folder to initialise in-place
// (used as-is); otherwise a fresh folder is minted from `name`.
export const createProject = (
  name: string,
  context: CompanyContext | null = null,
  targetPath: string | null = null,
): Promise<ProjectItem> =>
  invoke<ProjectItem>("create_project", { name, context, targetPath });

// Inspects an existing-folder init target so the UI can decide whether to
// confirm a potentially destructive overwrite before calling createProject.
export const inspectInitTarget = (path: string): Promise<InitTargetInfo> =>
  invoke<InitTargetInfo>("inspect_init_target", { path });

// Re-installs the latest module over an existing project and refreshes its
// managed AGENTS.md blocks. Init output streams on the project-create channel.
export const updateProject = (path: string): Promise<void> =>
  invoke("update_project", { path });

// Returns the paths of projects whose installed module version is behind the
// repo's latest. One repo fetch + N local manifest reads; empty on any failure.
export const checkForUpdates = (): Promise<string[]> =>
  invoke<string[]>("check_for_updates");

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

export const setGithubToken = (token: string): Promise<void> =>
  invoke("set_github_token", { token });

export const hasGithubToken = (): Promise<boolean> =>
  invoke<boolean>("has_github_token");

export const syncSkillsClaude = (): Promise<void> =>
  invoke("sync_skills_claude");

export const syncSkillsCodex = (): Promise<void> =>
  invoke("sync_skills_codex");

// Auto-sync both tools from the shared skills repo (skills + context/).
// No-op when the repo URL/token isn't configured.
export const syncSkillsRepo = (): Promise<void> =>
  invoke("sync_skills_repo");

// --- Contribution ---

export const listContributableItems = (): Promise<ContributableItems> =>
  invoke<ContributableItems>("list_contributable_items");

export const setContributorToken = (token: string): Promise<void> =>
  invoke("set_contributor_token", { token });

export const hasContributorToken = (): Promise<boolean> =>
  invoke<boolean>("has_contributor_token");

export const testRepoAccess = (): Promise<RepoAccessReport> =>
  invoke<RepoAccessReport>("test_repo_access");

export const submitContribution = (
  request: ContributionRequest,
): Promise<ContributionResult> =>
  invoke<ContributionResult>("submit_contribution", { request });
