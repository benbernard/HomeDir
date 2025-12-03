#!/usr/bin/env tsx

import { execSync } from "child_process";
import {
  appendFileSync,
  existsSync,
  lstatSync,
  readFileSync,
  readlinkSync,
  readdirSync,
  realpathSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "fs";
import { homedir } from "os";
import { basename, join } from "path";
import chalk from "chalk";
import { dedent } from "ts-dedent";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import { logError, logInfo, logSuccess } from "./lib/logger";
import { prompt } from "./lib/prompts";

interface CommandResult {
  exitCode: number;
}

interface IcConfig {
  hooks?: Record<string, string[]>;
  autoDetect?: Record<string, string[]>;
}

let shellIntegrationScript: string | undefined;

function outputCommand(cmd: string): void {
  if (shellIntegrationScript) {
    // Append command to script file
    appendFileSync(shellIntegrationScript, `${cmd}\n`);
  } else {
    // Print in human-readable format for debugging
    console.log(`Would run: ${cmd}`);
  }
}

function outputScript(scriptContent: string): void {
  if (shellIntegrationScript) {
    // Write script content directly to file
    writeFileSync(shellIntegrationScript, scriptContent, { encoding: "utf-8" });
  } else {
    // Print in human-readable format for debugging
    console.log("Would run script:");
    console.log(scriptContent);
  }
}

/**
 * Get the repos directory from cdrp config or fallback to ~/repos
 */
export function getReposDir(): string {
  const cdrpConfigPath = join(homedir(), ".config", "ei", "cdrp_dir");

  if (existsSync(cdrpConfigPath)) {
    try {
      const reposDir = readFileSync(cdrpConfigPath, "utf-8").trim();
      if (reposDir && existsSync(reposDir)) {
        return reposDir;
      }
    } catch {
      // Fall through to default
    }
  }

  // Default to ~/repos
  return join(homedir(), "repos");
}

export function loadIcConfig(): IcConfig {
  const configPath = join(homedir(), ".icrc.json");

  if (!existsSync(configPath)) {
    // Return default config
    return {
      autoDetect: {
        "package.json": ["npm install"],
        Gemfile: ["bundle install"],
        "requirements.txt": ["pip install -r requirements.txt"],
        "go.mod": ["go mod download"],
      },
    };
  }

  try {
    const configContent = readFileSync(configPath, "utf-8");
    const config = JSON.parse(configContent) as IcConfig;

    // Merge with defaults if autoDetect is not provided
    if (!config.autoDetect) {
      config.autoDetect = {
        "package.json": ["npm install"],
        Gemfile: ["bundle install"],
        "requirements.txt": ["pip install -r requirements.txt"],
        "go.mod": ["go mod download"],
      };
    }

    return config;
  } catch (error) {
    logError(`Failed to load config from ${configPath}: ${error}`);
    return {
      autoDetect: {
        "package.json": ["npm install"],
        Gemfile: ["bundle install"],
        "requirements.txt": ["pip install -r requirements.txt"],
        "go.mod": ["go mod download"],
      },
    };
  }
}

export function detectRepoFiles(repoDir: string): string[] {
  const detectedFiles: string[] = [];
  const filesToCheck = [
    "package.json",
    "Gemfile",
    "requirements.txt",
    "go.mod",
  ];

  for (const file of filesToCheck) {
    if (existsSync(join(repoDir, file))) {
      detectedFiles.push(file);
    }
  }

  return detectedFiles;
}

export function resolveSetupHooks(
  config: IcConfig,
  repoIdentifier: string,
  detectedFiles: string[],
): string[] {
  // First check for exact repo identifier match (user/repo format)
  if (config.hooks?.[repoIdentifier]) {
    return config.hooks[repoIdentifier];
  }

  // If no exact match, use autoDetect based on detected files
  const commands: string[] = [];
  if (config.autoDetect) {
    for (const file of detectedFiles) {
      if (config.autoDetect[file]) {
        commands.push(...config.autoDetect[file]);
      }
    }
  }

  return commands;
}

/**
 * Parse GitHub URL or user/repo format and extract user and repo name.
 * Supports:
 * - https://github.com/user/repo
 * - https://github.com/user/repo.git
 * - git@github.com:user/repo.git
 * - git@github.com:user/repo
 * - user/repo
 * - repo (defaults to instacart)
 */
export function parseGitHubInput(
  input: string,
): { user: string; repo: string } | null {
  // Remove trailing slashes
  const trimmedInput = input.trim().replace(/\/$/, "");

  // Pattern 1: HTTPS URL
  const httpsMatch = trimmedInput.match(
    /^https?:\/\/github\.com\/([^\/]+)\/([^\/]+?)(\.git)?$/,
  );
  if (httpsMatch) {
    return { user: httpsMatch[1], repo: httpsMatch[2] };
  }

  // Pattern 2: SSH URL (git@github.com:user/repo.git or git@github.com:user/repo)
  const sshMatch = trimmedInput.match(
    /^git@github\.com:([^\/]+)\/(.+?)(\.git)?$/,
  );
  if (sshMatch) {
    return { user: sshMatch[1], repo: sshMatch[2] };
  }

  // Pattern 3: user/repo format
  if (trimmedInput.includes("/")) {
    const parts = trimmedInput.split("/");
    if (parts.length === 2) {
      return { user: parts[0], repo: parts[1] };
    }
  }

  // Pattern 4: Just repo name, default to instacart
  if (
    trimmedInput &&
    !trimmedInput.includes("/") &&
    !trimmedInput.includes(":")
  ) {
    return { user: "instacart", repo: trimmedInput };
  }

  return null;
}

/**
 * Detect if the given path is within a workspace directory structure.
 * Returns the workspace name if detected, null otherwise.
 *
 * Examples:
 *   ~/repos/myFeature/ava -> "myFeature"
 *   ~/repos/myFeature -> "myFeature" (if it contains subdirectories)
 *   ~/repos/standalone-repo -> null
 */
export function detectWorkspace(path: string): string | null {
  const reposDir = getReposDir();

  // Check if path is under ~/repos
  if (!path.startsWith(reposDir)) {
    return null;
  }

  // Get relative path from repos dir
  const relativePath = path.slice(reposDir.length + 1);
  const parts = relativePath.split("/").filter((p) => p.length > 0);

  if (parts.length === 0) {
    // We're exactly at ~/repos
    return null;
  }

  if (parts.length >= 2) {
    // We're in a subdirectory like ~/repos/myFeature/ava
    // First part is the workspace name
    return parts[0];
  }

  if (parts.length === 1) {
    // We're at ~/repos/something
    // Check if this directory is a workspace (no .git) or a standalone repo (has .git)
    const potentialWorkspace = join(reposDir, parts[0]);

    if (!existsSync(potentialWorkspace)) {
      return null;
    }

    // If it has a .git directory, it's a standalone repo, not a workspace
    const gitDir = join(potentialWorkspace, ".git");
    if (existsSync(gitDir)) {
      return null;
    }

    // No .git directory means it's a workspace
    return parts[0];
  }

  return null;
}

/**
 * Check if the given path is exactly a workspace directory (not a repo within it).
 * Returns true if path is ~/repos/<workspace>, false otherwise.
 */
function isWorkspaceDir(path: string): boolean {
  const reposDir = getReposDir();

  if (!path.startsWith(reposDir)) {
    return false;
  }

  const relativePath = path.slice(reposDir.length + 1);
  const parts = relativePath.split("/").filter((p) => p.length > 0);

  // It's a workspace dir if we're exactly one level deep
  return parts.length === 1;
}

async function cloneCommand(
  input: string,
  workspaceFlag?: string,
): Promise<CommandResult> {
  if (!input) {
    logError("Usage: ic clone <user/repo> or <repo> or <github-url>");
    return { exitCode: 1 };
  }

  // Parse input to extract user and repo
  const parsed = parseGitHubInput(input);
  if (!parsed) {
    logError(`Invalid input format: ${input}`);
    logError("Expected: user/repo, repo, or GitHub URL");
    return { exitCode: 1 };
  }

  const { user, repo } = parsed;

  // Determine workspace context
  const currentDir = process.cwd();
  const currentWorkspace = detectWorkspace(currentDir);
  let targetWorkspace: string | null = null;

  if (workspaceFlag) {
    // Explicit workspace flag provided
    targetWorkspace = workspaceFlag;
  } else if (currentWorkspace) {
    // We're in a workspace directory, prompt for choice
    const response = await prompt(
      `Clone into workspace '${currentWorkspace}' or globally? [workspace/GLOBAL]`,
      "GLOBAL",
    );

    const choice = response.toUpperCase().trim();
    if (choice === "WORKSPACE" || choice === "W") {
      targetWorkspace = currentWorkspace;
    }
    // Otherwise targetWorkspace stays null (global clone)
  }

  const repoUrl = `git@github.com:${user}/${repo}.git`;
  const reposDir = getReposDir();
  let repoDir: string;

  if (targetWorkspace) {
    // Clone into workspace
    repoDir = join(reposDir, targetWorkspace, repo);
  } else {
    // Clone globally to ~/repos
    repoDir = join(reposDir, repo);
  }

  // Handle directory collision with prompt
  if (existsSync(repoDir)) {
    logInfo(`Directory ${repoDir} already exists`);
    const suffix = await prompt(
      `Enter a suffix for the directory name (will be ${repo}-<suffix>)`,
      "",
    );

    const newName = suffix ? `${repo}-${suffix}` : `${repo}-`;
    repoDir = join(reposDir, newName);

    // Check again if the new directory exists
    if (existsSync(repoDir)) {
      logError(`Directory ${repoDir} already exists, aborting`);
      return { exitCode: 1 };
    }
  }

  // Create repo directory
  execSync(`mkdir -p "${repoDir}"`, { stdio: "inherit" });

  // Clone with SSH
  logInfo(`Cloning ${repoUrl} to ${repoDir}...`);
  try {
    execSync(`git clone "${repoUrl}" "${repoDir}"`, {
      stdio: "inherit",
    });
  } catch {
    logError("Failed to clone repository");
    return { exitCode: 1 };
  }

  if (targetWorkspace) {
    logSuccess(
      `Successfully cloned to workspace '${targetWorkspace}': ${repoDir}`,
    );
  } else {
    logSuccess(`Successfully cloned to ${repoDir}`);
  }

  // Run setup hooks
  const config = loadIcConfig();
  const detectedFiles = detectRepoFiles(repoDir);
  const repoIdentifier = `${user}/${repo}`;
  const hooks = resolveSetupHooks(config, repoIdentifier, detectedFiles);

  if (hooks.length > 0) {
    logInfo(`Running setup hooks for ${repoIdentifier}...`);
    for (const command of hooks) {
      logInfo(`Running: ${command}`);
      try {
        execSync(command, {
          cwd: repoDir,
          stdio: "inherit",
        });
        logSuccess(`Completed: ${command}`);
      } catch (error) {
        logError(`Failed to run: ${command}`);
        // Continue with remaining hooks and don't abort
      }
    }
    logSuccess("Setup hooks completed");
  }

  outputCommand(`cd "${repoDir}"`);
  return { exitCode: 0 };
}

interface SessionStatus {
  exists: boolean;
  isAttached: boolean;
}

/**
 * Execute a tmux command on the nested socket with the nested config file.
 * Automatically prepends "tmux -L nested -f ~/.tmux.nested.conf" to the command.
 */
function execNestedTmux(
  command: string,
  options?: Parameters<typeof execSync>[1],
): ReturnType<typeof execSync> {
  const fullCommand = `tmux -L nested -f ~/.tmux.nested.conf ${command}`;
  return execSync(fullCommand, options);
}

function checkSessionStatus(sessionName: string): SessionStatus {
  let sessionExists = false;
  let isAttached = false;

  try {
    // Check on nested socket (-L nested)
    // Use exact match by prefixing '=' to prevent partial matching (e.g., 'olive' matching 'olive-server')
    execNestedTmux(`has-session -t \"=${sessionName}\" 2>&1`, {
      stdio: "pipe",
    });
    sessionExists = true;

    try {
      // Use exact match for list-clients as well
      const clients = (
        execNestedTmux(`list-clients -t \"=${sessionName}\" 2>&1`, {
          encoding: "utf-8",
        }) as string
      ).trim();
      isAttached = clients.length > 0;
    } catch {
      isAttached = false;
    }
  } catch {
    sessionExists = false;
  }

  return { exists: sessionExists, isAttached };
}

async function attachCommand(
  force: boolean,
  cwd: boolean,
): Promise<CommandResult> {
  // Check if in tmux
  if (!process.env.TMUX) {
    logError("Not in a tmux session");
    return { exitCode: 1 };
  }

  // Check if already in a nested tmux session
  try {
    const tmuxInfo = execSync(
      'tmux display-message -p "#{session_name}|#{pane_title}|#{window_name}"',
      {
        encoding: "utf-8",
      },
    ).trim();

    const [sessionName, paneTitle, windowName] = tmuxInfo.split("|");

    // Detect nested tmux by checking window/pane titles
    const isNested =
      windowName.startsWith("nt:") ||
      windowName.startsWith("ic:") ||
      paneTitle.startsWith("nt:") ||
      paneTitle.startsWith("ic:") ||
      paneTitle.includes("Nested TM"); // Fallback for generic nested indicator

    if (isNested) {
      logError(
        `Already in a nested tmux session (window: '${windowName}'). Detach first.`,
      );
      return { exitCode: 1 };
    }
  } catch {
    // Ignore errors, continue
  }

  // Always use current working directory (--cwd is implied)
  const currentDir = process.cwd();

  // Check if we're in a workspace directory
  const workspace = detectWorkspace(currentDir);

  let repoRoot: string;
  let repoDirName: string;
  let isWorkspaceSession = false;

  if (workspace) {
    // We're in a workspace - always attach at workspace level
    const reposDir = getReposDir();
    repoRoot = join(reposDir, workspace);
    repoDirName = workspace;
    isWorkspaceSession = true;

    logInfo(`Detected workspace '${workspace}', attaching at workspace level`);
  } else {
    // Not in a workspace, use existing git repo logic
    // Check if we're in a git repository and if we're at the root
    let gitRoot: string | null = null;
    try {
      gitRoot = execSync("git rev-parse --show-toplevel", {
        encoding: "utf-8",
        cwd: currentDir,
      }).trim();
    } catch {
      // Not in a git repository - that's okay, we'll use currentDir
    }

    // If we're in a git repo but not at the root, prompt for choice
    if (gitRoot && gitRoot !== currentDir) {
      // Check session status for both locations
      const cwdSessionName = `ic_${basename(currentDir)}`;
      const rootSessionName = `ic_${basename(gitRoot)}`;
      const cwdStatus = checkSessionStatus(cwdSessionName);
      const rootStatus = checkSessionStatus(rootSessionName);

      // Build status strings
      const cwdStatusStr = cwdStatus.exists
        ? cwdStatus.isAttached
          ? " (session exists & attached)"
          : " (session exists)"
        : " (no session)";
      const rootStatusStr = rootStatus.exists
        ? rootStatus.isAttached
          ? " (session exists & attached)"
          : " (session exists)"
        : " (no session)";

      // Prompt for choice
      const response = await prompt(
        `Not at git repo root. Choose:\n  [CWD] Current dir: ${currentDir}${cwdStatusStr}\n  [ROOT] Git root: ${gitRoot}${rootStatusStr}\nChoice`,
        "CWD",
      );

      const choice = response.toUpperCase().trim();
      if (choice === "ROOT" || choice === "R") {
        repoRoot = gitRoot;
        repoDirName = basename(gitRoot);
      } else if (choice === "CWD" || choice === "C" || choice === "") {
        repoRoot = currentDir;
        repoDirName = basename(currentDir);
      } else {
        logInfo("Aborted");
        return { exitCode: 0 };
      }
    } else {
      // At root or not in git repo, use current directory
      repoRoot = currentDir;
      repoDirName = basename(repoRoot);
    }
  }

  // Create session name
  // Use workspace naming for workspace sessions, regular naming otherwise
  const sessionName = isWorkspaceSession
    ? `ic_ws_${repoDirName}`
    : `ic_${repoDirName}`;

  // Check if session already exists on nested socket using helper
  // Note: checkSessionStatus needs to be updated to support -L flag
  const sessionStatus = checkSessionStatus(sessionName);
  const sessionExists = sessionStatus.exists;
  const isAttached = sessionStatus.isAttached;

  // Track if we need to cd to repoRoot
  // For workspace sessions: cd if not at workspace root
  // For regular sessions: cd if ROOT was chosen and not already there
  const needsCd = currentDir !== repoRoot;

  if (sessionExists) {
    if (isAttached) {
      // Session is attached
      if (force) {
        logInfo(
          `Session '${sessionName}' is attached, detaching other clients...`,
        );
        // Detach all other clients
        try {
          execNestedTmux(`detach-client -s "${sessionName}" -a`, {
            stdio: "pipe",
          });
        } catch {
          // Ignore errors
        }
      } else {
        logError(
          `Session '${sessionName}' is already attached. Use --force to detach other clients.`,
        );
        return { exitCode: 1 };
      }
    }

    // Session exists and not attached (or we detached others), attach to it
    logInfo(`Attaching to existing session '${sessionName}'...`);

    const cdPrefix = needsCd ? `cd "${repoRoot}"\n        ` : "";
    const attachExistingScript = dedent`
      (
        ${cdPrefix}printf '\\033kic: ${repoDirName}\\033\\\\'

        env -u TMUX tmux -L nested -f ~/.tmux.nested.conf attach-session -t "${sessionName}"
      )
    `;

    outputScript(attachExistingScript);
    return { exitCode: 0 };
  }

  // Session doesn't exist, create it
  logInfo(`Creating new session '${sessionName}'...`);

  // Create a script that sets up nested tmux session and attaches to it
  const cdPrefixForCreate = needsCd ? `cd "${repoRoot}"\n      ` : "";
  const createScript = dedent`
    (
      ${cdPrefixForCreate}printf '\\033kic: ${repoDirName}\\033\\\\'

      env -u TMUX tmux -L nested -f ~/.tmux.nested.conf new-session -d -s "${sessionName}" -c "${repoRoot}"
      env -u TMUX tmux -L nested -f ~/.tmux.nested.conf new-window -t "${sessionName}:1" -c "${repoRoot}"
      env -u TMUX tmux -L nested -f ~/.tmux.nested.conf new-window -t "${sessionName}:2" -c "${repoRoot}"
      env -u TMUX tmux -L nested -f ~/.tmux.nested.conf select-window -t "${sessionName}:0"
      env -u TMUX tmux -L nested -f ~/.tmux.nested.conf attach-session -t "${sessionName}"
    )
  `;

  outputScript(createScript);

  return { exitCode: 0 };
}

async function workspaceStartCommand(name?: string): Promise<CommandResult> {
  const reposDir = getReposDir();
  let workspaceName = name;

  if (!workspaceName) {
    // No name provided, try to infer from current directory
    const currentDir = process.cwd();

    // Check if we're one level under repos dir
    if (currentDir.startsWith(reposDir)) {
      const relativePath = currentDir.slice(reposDir.length + 1);
      const parts = relativePath.split("/").filter((p) => p.length > 0);

      if (parts.length === 1) {
        // We're at ~/repos/something - use this as workspace name
        workspaceName = parts[0];
      }
    }

    if (!workspaceName) {
      logError(
        "Must provide workspace name or run from a directory under repos",
      );
      logError("Usage: ic workspace start <name>");
      logError("   or: cd ~/repos/myWorkspace && ic workspace start");
      return { exitCode: 1 };
    }
  }

  const workspaceDir = join(reposDir, workspaceName);

  // Check if directory exists
  if (!existsSync(workspaceDir)) {
    // Create the workspace directory
    try {
      execSync(`mkdir -p "${workspaceDir}"`, { stdio: "inherit" });
      logSuccess(`Created workspace directory: ${workspaceDir}`);
    } catch (error) {
      logError(`Failed to create workspace directory: ${error}`);
      return { exitCode: 1 };
    }
  } else {
    // Directory exists, check if it's already a workspace or a repo
    const gitDir = join(workspaceDir, ".git");
    if (existsSync(gitDir)) {
      logError(
        `Directory ${workspaceDir} is a git repository, not a workspace`,
      );
      return { exitCode: 1 };
    }

    const workspaceFile = join(workspaceDir, ".workspace");
    if (existsSync(workspaceFile)) {
      logInfo(`Workspace '${workspaceName}' already exists at ${workspaceDir}`);
      return { exitCode: 0 };
    }
  }

  // Create .workspace file
  const workspaceFile = join(workspaceDir, ".workspace");
  try {
    writeFileSync(workspaceFile, "", { encoding: "utf-8" });
    logSuccess(`Created workspace '${workspaceName}' at ${workspaceDir}`);
  } catch (error) {
    logError(`Failed to create .workspace file: ${error}`);
    return { exitCode: 1 };
  }

  // Change to the workspace directory
  outputCommand(`cd "${workspaceDir}"`);

  return { exitCode: 0 };
}

async function symlinkShowCommand(all: boolean): Promise<CommandResult> {
  const home = homedir();
  const currentDir = process.cwd();
  const reposDir = getReposDir();

  // Try to find git root
  let gitRoot: string | null = null;
  try {
    gitRoot = execSync("git rev-parse --show-toplevel", {
      encoding: "utf-8",
      cwd: currentDir,
    }).trim();
  } catch {
    // Not in a git repository - that's ok, we'll show all symlinks without marking current
  }

  // Get all items in home directory
  const items = readdirSync(home);
  const symlinks: Array<{ name: string; target: string; isCurrent: boolean }> =
    [];

  for (const item of items) {
    const itemPath = join(home, item);
    try {
      const stats = lstatSync(itemPath);
      if (stats.isSymbolicLink()) {
        const target = readlinkSync(itemPath);
        let resolvedTarget: string;
        try {
          resolvedTarget = realpathSync(itemPath);
        } catch {
          resolvedTarget = target; // Broken link, use raw target
        }

        // Skip unless --all or points into repos directory
        if (!all && !resolvedTarget.startsWith(reposDir)) {
          continue;
        }

        const isCurrent = gitRoot !== null && resolvedTarget === gitRoot;
        symlinks.push({ name: item, target: resolvedTarget, isCurrent });
      }
    } catch {
      // Skip items we can't read
      continue;
    }
  }

  if (symlinks.length === 0) {
    if (all) {
      console.log("No symlinks found in home directory");
    } else {
      console.log(`No symlinks found pointing to ${reposDir}`);
    }
    return { exitCode: 0 };
  }

  // Sort symlinks alphabetically
  symlinks.sort((a, b) => a.name.localeCompare(b.name));

  // Calculate column widths for table formatting
  const maxNameLen = Math.max(...symlinks.map((s) => s.name.length));
  const nameWidth = Math.max(maxNameLen, 8); // Minimum 8 for "SYMLINK" header

  // Print header
  console.log(
    `${chalk.bold("SYMLINK".padEnd(nameWidth))}  ${chalk.bold("TARGET")}`,
  );

  // Print symlinks
  for (const { name, target, isCurrent } of symlinks) {
    const nameCol = isCurrent
      ? chalk.green(name.padEnd(nameWidth))
      : name.padEnd(nameWidth);
    const marker = isCurrent ? chalk.green(" *") : "";
    console.log(`${nameCol}  ${target}${marker}`);
  }

  return { exitCode: 0 };
}

async function symlinkCreateCommand(force: boolean): Promise<CommandResult> {
  const currentDir = process.cwd();
  const home = homedir();

  // Try to find git root
  let gitRoot: string | null = null;
  try {
    gitRoot = execSync("git rev-parse --show-toplevel", {
      encoding: "utf-8",
      cwd: currentDir,
    }).trim();
  } catch {
    logError("Not in a git repository");
    logError(
      "The symlink command must be run from within a git repository directory",
    );
    return { exitCode: 1 };
  }

  // Get repo name from git root
  const repoName = basename(gitRoot);
  const symlinkPath = join(home, repoName);

  // Check if symlink path already exists
  if (existsSync(symlinkPath)) {
    const stats = lstatSync(symlinkPath);

    if (stats.isSymbolicLink()) {
      // It's a symlink, check where it points
      const currentTarget = readlinkSync(symlinkPath);
      const resolvedTarget = realpathSync(symlinkPath);

      if (resolvedTarget === gitRoot) {
        logInfo(
          `Symlink ~/${repoName} already points to ${gitRoot}. Nothing to do.`,
        );
        return { exitCode: 0 };
      }

      // Symlink exists but points elsewhere
      if (!force) {
        const response = await prompt(
          `Symlink ~/${repoName} exists pointing to ${currentTarget}. Update to ${gitRoot}? [y/N]`,
          "N",
        );

        const choice = response.toUpperCase().trim();
        if (choice !== "Y" && choice !== "YES") {
          logInfo("Aborted");
          return { exitCode: 0 };
        }
      } else {
        logInfo(
          `Updating symlink ~/${repoName} from ${currentTarget} to ${gitRoot}...`,
        );
      }

      // Remove old symlink and create new one
      try {
        unlinkSync(symlinkPath);
        symlinkSync(gitRoot, symlinkPath);
        logSuccess(`Updated symlink ~/${repoName} -> ${gitRoot}`);
        return { exitCode: 0 };
      } catch (error) {
        logError(`Failed to update symlink: ${error}`);
        return { exitCode: 1 };
      }
    } else {
      // It's a regular file or directory
      logError(
        `~/${repoName} exists as a regular ${
          stats.isDirectory() ? "directory" : "file"
        }, not a symlink`,
      );
      logError(
        "Cannot create symlink. Please remove or rename the existing item first",
      );
      return { exitCode: 1 };
    }
  }

  // Symlink doesn't exist, create it
  try {
    symlinkSync(gitRoot, symlinkPath);
    logSuccess(`Created symlink ~/${repoName} -> ${gitRoot}`);
    return { exitCode: 0 };
  } catch (error) {
    logError(`Failed to create symlink: ${error}`);
    return { exitCode: 1 };
  }
}

function showHelp(): void {
  console.log(dedent`
    IC - Simple Git Clone & Attach Manager

    Usage:
      ic clone|c <user/repo> [-w <workspace>]  Clone repo to ~/repos with SSH
      ic clone|c <repo> [-w <workspace>]       Clone repo (defaults to instacart/<repo>)
      ic clone|c <github-url> [-w <workspace>] Clone from GitHub URL (HTTPS or SSH)
      ic attach|a [--force] [--cwd]            Attach to nested tmux session (create if needed)
      ic symlink|s [show] [--all]              Show repo symlinks (or all with --all)
      ic symlink|s create [--force]            Create ~/REPO symlink to current repo
      ic workspace start [name]                Create a new workspace directory
      ic ws start [name]                       Alias for workspace start
      ic --help|-h|help                        Show this help message

    Examples:
      ic c user/repo                     # Clone git@github.com:user/repo.git
      ic c myrepo                        # Clone git@github.com:instacart/myrepo.git
      ic c myrepo -w myFeature           # Clone into ~/repos/myFeature/myrepo
      ic c https://github.com/user/repo     # Clone from HTTPS URL
      ic c git@github.com:user/repo.git     # Clone from SSH URL
      ic ws start myFeature              # Create workspace ~/repos/myFeature
      ic a                               # Attach to nested tmux (create if needed)
      ic a --force                       # Detach other clients and attach
      ic a --cwd                         # Use current directory (deprecated, always implied)
      ic s                               # Show symlinks pointing to repos
      ic s --all                         # Show all symlinks in home directory
      ic s create                        # Create ~/myrepo -> /path/to/myrepo symlink
      ic s create --force                # Update symlink without confirmation
  `);
}

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .option("shell-integration-script", {
      type: "string",
      description: "File path for shell integration script",
      hidden: true,
    })
    .command(
      ["clone <repo>", "c <repo>"],
      "Clone a GitHub repo with SSH",
      (yargs) => {
        return yargs
          .positional("repo", {
            describe: "Repository in format user/repo or just repo",
            type: "string",
          })
          .option("workspace", {
            alias: "w",
            type: "string",
            description: "Clone into a workspace directory",
          });
      },
    )
    .command(
      ["attach", "a"],
      "Attach current repo to nested tmux session",
      (yargs) => {
        return yargs
          .option("force", {
            type: "boolean",
            description: "Detach other clients and attach",
            default: false,
          })
          .option("cwd", {
            type: "boolean",
            description:
              "Use current working directory (deprecated, always implied)",
            default: true,
          });
      },
    )
    .command(
      ["workspace start [name]", "ws start [name]"],
      "Create a new workspace directory",
      (yargs) => {
        return yargs.positional("name", {
          describe: "Workspace name",
          type: "string",
        });
      },
    )
    .command(
      ["symlink [subcommand]", "s [subcommand]"],
      "Manage symlinks for current repo",
      (yargs) => {
        return yargs
          .positional("subcommand", {
            describe: "Subcommand to run (show or create)",
            type: "string",
            choices: ["show", "create"],
            default: "show",
          })
          .option("all", {
            type: "boolean",
            description: "Show all symlinks in home directory (for show)",
            default: false,
          })
          .option("force", {
            type: "boolean",
            description: "Skip confirmation prompts (for create)",
            default: false,
          });
      },
    )
    .command(["help", "--help", "-h"], "Show help message")
    .help(false)
    .version(false)
    .parse();

  // Set the shell integration script file if provided
  shellIntegrationScript = argv["shell-integration-script"] as
    | string
    | undefined;

  const command = argv._[0] as string | undefined;
  const subcommand = argv._[1] as string | undefined;

  let result: CommandResult;

  if (command === "clone" || command === "c") {
    result = await cloneCommand(
      argv.repo as string,
      argv.workspace as string | undefined,
    );
  } else if (command === "attach" || command === "a") {
    result = await attachCommand(argv.force as boolean, argv.cwd as boolean);
  } else if (
    (command === "workspace" || command === "ws") &&
    subcommand === "start"
  ) {
    result = await workspaceStartCommand(argv.name as string | undefined);
  } else if (command === "symlink" || command === "s") {
    // Get subcommand from argv (yargs will default to 'show')
    const symlinkSubcommand = (argv.subcommand as string) || "show";

    if (symlinkSubcommand === "show") {
      result = await symlinkShowCommand(argv.all as boolean);
    } else if (symlinkSubcommand === "create") {
      result = await symlinkCreateCommand(argv.force as boolean);
    } else {
      logError(`Unknown symlink subcommand: ${symlinkSubcommand}`);
      logError("Available subcommands: show, create");
      result = { exitCode: 1 };
    }
  } else if (command === "help" || argv.help) {
    showHelp();
    result = { exitCode: 0 };
  } else {
    logError("No command specified");
    showHelp();
    result = { exitCode: 1 };
  }

  process.exit(result.exitCode);
}

// Only run main if this is the entry point (not imported)
// Use realpathSync to handle symlinks and macOS /private prefix
function isEntryPoint(): boolean {
  try {
    const importPath = new URL(import.meta.url).pathname;
    const argvPath = process.argv[1];
    // Resolve both paths to handle symlinks and /private prefix on macOS
    const resolvedImport = realpathSync(importPath);
    const resolvedArgv = realpathSync(argvPath);
    return resolvedImport === resolvedArgv;
  } catch {
    return false;
  }
}

if (isEntryPoint()) {
  main().catch((error) => {
    logError(`Unexpected error: ${error}`);
    process.exit(1);
  });
}
