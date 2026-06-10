// Mirror of the Rust models in src-tauri/src/models/. Keep field names
// aligned with the camelCase serde renames so structures round-trip
// through the IPC layer without manual translation.

export type ProjectSortOrder =
  | "nameAscending"
  | "dateNewestFirst"
  | "dateOldestFirst";

export type ModuleSourceKind = "gitRepo" | "localZip";

export type TerminalKind =
  | "terminal"
  | "iterm2"
  | "windowsTerminal"
  | "cmd";

export interface AppSettings {
  projectsRoot: string;
  moduleSourceKind: ModuleSourceKind;
  moduleRepoUrl: string;
  moduleRepoRef: string;
  moduleZipPath: string;
  initCommand: string;
  claudeCommand: string;
  opencodeCommand: string;
  piCommand: string;
  projectSortOrder: ProjectSortOrder;
  terminalKind: TerminalKind;
}

export interface ProjectItem {
  name: string;
  path: string;
  createdAt: number | null;
}

export type OutputEvent =
  | { kind: "stdout"; line: string }
  | { kind: "stderr"; line: string }
  | { kind: "exit"; code: number };

export interface BundledTooling {
  nodeVersion: string | null;
  gitVersion: string | null;
}

export const projectSortOrderOptions: { value: ProjectSortOrder; label: string }[] = [
  { value: "nameAscending", label: "Name (A→Z)" },
  { value: "dateNewestFirst", label: "Date created (newest first)" },
  { value: "dateOldestFirst", label: "Date created (oldest first)" },
];

export const moduleSourceOptions: { value: ModuleSourceKind; label: string }[] = [
  { value: "gitRepo", label: "GitHub repo" },
  { value: "localZip", label: "Local zip" },
];

export const terminalOptions: { value: TerminalKind; label: string }[] = [
  { value: "windowsTerminal", label: "Windows Terminal" },
  { value: "cmd", label: "Command Prompt" },
];
