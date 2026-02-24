/**
 * Script Manifest
 *
 * This file defines all executable scripts in bin/ts/src.
 * The build process uses this to generate symlinks in both src/ and dist/.
 *
 * To add a new script:
 * 1. Create the TypeScript file in src/ with shebang: #!/usr/bin/env tsx
 * 2. Add an entry to this manifest with a clear description
 * 3. Run `npm run build` to generate symlinks
 */

export interface ScriptEntry {
  /** Source file in src/ (e.g., "ic.ts") */
  file: string;
  /** Human-readable description of what the script does */
  description: string;
}

/**
 * All executable scripts.
 * Key is the command name (what you type to run it).
 * Value contains the source file and description.
 */
export const scripts: Record<string, ScriptEntry> = {
  // Session and environment management
  ic: {
    file: "ic.ts",
    description:
      "Tmux session manager with project detection and shell integration",
  },
  // Git utilities
  "git-cleanup": {
    file: "git-cleanup.ts",
    description:
      "Delete local and remote branches that have been merged to main",
  },
  "git-prune-old": {
    file: "git-prune-old.ts",
    description: "Delete branches older than N days (default: 30)",
  },
  "close-prs": {
    file: "close-prs.ts",
    description:
      "Bulk close GitHub PRs with filters (age, author, draft status)",
  },

  // File and download utilities
  "read-tree": {
    file: "read-tree.ts",
    description: "Recursively read directory tree and output file contents",
  },
  downloader: {
    file: "downloader.ts",
    description:
      "Download queue manager with clipboard URL extraction (DynamoDB-backed)",
  },
  s3upload: {
    file: "s3upload.ts",
    description: "Upload files to S3 bucket with automatic URL generation",
  },

  // Shell analysis
  "analyze-zsh-startup": {
    file: "analyze-zsh-startup.ts",
    description: "Analyze zsh startup timing, show slowest entries",
  },
  "analyze-by-file": {
    file: "analyze-by-file.ts",
    description: "Analyze zsh startup log by source file",
  },

  // Claude Code integration
  "claude-notify": {
    file: "claude-notify.ts",
    description: "Claude Code hook for macOS notifications on task completion",
  },

  // Email utilities
  converter: {
    file: "converter.ts",
    description: "Convert maildir email format to mbox format",
  },

  // Tmux integration
  "tmux-fzf-picker": {
    file: "tmux-fzf-picker.ts",
    description:
      "Fzf file/directory picker for tmux popups with toggle support",
  },

  // Meta
  "ben-scripts": {
    file: "ben-scripts.ts",
    description: "List all available scripts with descriptions",
  },
};

/**
 * Files that should be excluded from "missing from manifest" warnings.
 * These are library modules, test files, or other non-executable code.
 */
export const excludedFiles: string[] = [
  // Library modules (not meant to be run directly)
  "clipboard.ts",
  "db.ts",
  "download.ts",
  "cli.ts", // Template/example, not a real command

  // Debug/development variants
  "claude-notify-debug.ts",

  // The manifest itself
  "manifest.ts",
];
