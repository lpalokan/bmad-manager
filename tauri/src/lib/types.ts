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
  codexCommand: string;
  projectSortOrder: ProjectSortOrder;
  terminalKind: TerminalKind;
  skillsRepoUrl: string;
  skillsRepoBranch: string;
}

export interface ProjectItem {
  name: string;
  path: string;
  createdAt: number | null;
}

// Mirror of models/company_context.rs — RECOGNIZED_FILE_NAMES.
export const recognizedContextFileNames = [
  "icp.md",
  "positioning.md",
  "brand-voice.md",
  "kpis.md",
  "tech-stack.md",
] as const;

// Mirror of models/company_context.rs ContextSource (serde camelCase).
export type ContextSource = "project" | "github";

// Native <select> options can't embed image assets, so each source gets a
// trailing emoji marker: a folder (matching the project list's "open
// folder" button) for project-local contexts, and an octopus standing in
// for the GitHub octocat for contexts from the shared skills repo.
const contextSourceMarker: Record<ContextSource, string> = {
  project: "📂",
  github: "🐙",
};

export interface CompanyContext {
  projectName: string;
  directory: string;
  files: string[];
  // Optional for backward-compat with payloads predating the field.
  source?: ContextSource;
}

// Mirror of CompanyContext::display_name() in Rust: the source name with a
// trailing source marker, and a hint appended when the context is missing
// some of the recognized files.
export function companyContextDisplayName(context: CompanyContext): string {
  const total = recognizedContextFileNames.length;
  const base =
    context.files.length === total
      ? context.projectName
      : `${context.projectName} (${context.files.length} of ${total} context files)`;
  const marker = contextSourceMarker[context.source ?? "project"];
  return `${base} ${marker}`;
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
