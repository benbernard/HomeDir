#!/usr/bin/env tsx

import { execSync } from "child_process";
import {
  appendFileSync,
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
  readlinkSync,
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
 * Detect if the given path is within a workspace/project directory structure.
 * Returns the workspace/project name if detected, null otherwise.
 *
 * Examples:
 *   ~/repos/myFeature/ava -> "myFeature"
 *   ~/repos/myFeature -> "myFeature" (if it contains .ic_project or .workspace file)
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
    // Check if parent directory has project marker
    const potentialProject = join(reposDir, parts[0]);
    const hasProjectMarker =
      existsSync(join(potentialProject, ".ic_project")) ||
      existsSync(join(potentialProject, ".workspace"));

    if (hasProjectMarker) {
      return parts[0];
    }

    // Fallback: if no marker but parent has no .git, assume it's a project
    const gitDir = join(potentialProject, ".git");
    if (!existsSync(gitDir)) {
      return parts[0];
    }
  }

  if (parts.length === 1) {
    // We're at ~/repos/something
    const potentialProject = join(reposDir, parts[0]);

    if (!existsSync(potentialProject)) {
      return null;
    }

    // Check for project marker files
    const hasProjectMarker =
      existsSync(join(potentialProject, ".ic_project")) ||
      existsSync(join(potentialProject, ".workspace"));

    if (hasProjectMarker) {
      return parts[0];
    }

    // If it has a .git directory, it's a standalone repo, not a project
    const gitDir = join(potentialProject, ".git");
    if (existsSync(gitDir)) {
      return null;
    }

    // No .git directory and no marker - could be a project without marker yet
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

/**
 * Initialize a project directory with git repo, .gitignore, and .ic_project marker
 */
function initProjectDirectory(projectDir: string): void {
  // Create directory
  execSync(`mkdir -p "${projectDir}"`, { stdio: "inherit" });

  // Initialize git repo
  execSync("git init", { cwd: projectDir, stdio: "pipe" });

  // Create .gitignore with header
  const gitignorePath = join(projectDir, ".gitignore");
  const gitignoreContent = `# Project repos - managed by ic
# Each cloned repo is added here automatically

`;
  writeFileSync(gitignorePath, gitignoreContent, { encoding: "utf-8" });

  // Create .ic_project marker
  const projectMarkerFile = join(projectDir, ".ic_project");
  writeFileSync(projectMarkerFile, "", { encoding: "utf-8" });

  // Stage the initial files
  execSync("git add .gitignore .ic_project", {
    cwd: projectDir,
    stdio: "pipe",
  });
  execSync('git commit -m "Initialize project"', {
    cwd: projectDir,
    stdio: "pipe",
  });

  logSuccess(`Initialized project directory: ${projectDir}`);
}

/**
 * Add a repo directory to the project's .gitignore file
 */
function addRepoToProjectGitignore(
  projectDir: string,
  repoDirName: string,
): void {
  const gitignorePath = join(projectDir, ".gitignore");

  // Read current .gitignore
  let gitignoreContent = "";
  if (existsSync(gitignorePath)) {
    gitignoreContent = readFileSync(gitignorePath, "utf-8");
  }

  // Check if repo is already in .gitignore
  const lines = gitignoreContent.split("\n");
  const repoPattern = `/${repoDirName}`;
  if (lines.includes(repoPattern)) {
    // Already in .gitignore
    return;
  }

  // Add repo to .gitignore
  if (!gitignoreContent.endsWith("\n") && gitignoreContent.length > 0) {
    gitignoreContent += "\n";
  }
  gitignoreContent += `${repoPattern}\n`;
  writeFileSync(gitignorePath, gitignoreContent, { encoding: "utf-8" });

  // Commit the change
  try {
    execSync(
      `git add .gitignore && git commit -m "Add ${repoDirName} to gitignore"`,
      {
        cwd: projectDir,
        stdio: "pipe",
      },
    );
  } catch {
    // If commit fails (e.g., no changes), that's okay
  }
}

async function cloneCommand(
  input: string,
  projectFlag?: string,
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

  // Determine project context
  const currentDir = process.cwd();
  const currentProject = detectWorkspace(currentDir);
  let targetProject: string | null = null;

  if (projectFlag) {
    // Explicit project flag provided
    targetProject = projectFlag;
  } else if (currentProject) {
    // We're in a project directory, automatically use it
    targetProject = currentProject;
    logInfo(`Auto-detected project '${currentProject}', cloning into it`);
  }

  const repoUrl = `git@github.com:${user}/${repo}.git`;
  const reposDir = getReposDir();
  let repoDir: string;
  let projectDir: string | null = null;
  let repoDirName = repo; // Track the actual directory name (may change with suffix)

  if (targetProject) {
    // Clone into project
    projectDir = join(reposDir, targetProject);
    repoDir = join(projectDir, repo);
  } else {
    // Clone globally to ~/repos
    repoDir = join(reposDir, repo);
  }

  // Create project directory if needed
  if (projectDir && !existsSync(projectDir)) {
    try {
      initProjectDirectory(projectDir);
    } catch (error) {
      logError(`Failed to initialize project directory: ${error}`);
      return { exitCode: 1 };
    }
  }

  // Handle directory collision with prompt
  if (existsSync(repoDir)) {
    logInfo(`Directory ${repoDir} already exists`);
    const suffix = await prompt(
      `Enter a suffix for the directory name (will be ${repo}-<suffix>)`,
      "",
    );

    // Trim leading dashes from suffix since we add one
    const trimmedSuffix = suffix.replace(/^-+/, "");
    const newName = trimmedSuffix ? `${repo}-${trimmedSuffix}` : `${repo}-`;
    repoDirName = newName; // Update the tracked directory name
    if (projectDir) {
      repoDir = join(projectDir, newName);
    } else {
      repoDir = join(reposDir, newName);
    }

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

  if (targetProject) {
    logSuccess(`Successfully cloned to project '${targetProject}': ${repoDir}`);
    // Add repo to project's .gitignore
    if (projectDir) {
      addRepoToProjectGitignore(projectDir, repoDirName);
    }
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
    // Create and initialize the workspace directory
    try {
      initProjectDirectory(workspaceDir);
      // Also create .workspace marker for backward compatibility
      const workspaceFile = join(workspaceDir, ".workspace");
      writeFileSync(workspaceFile, "", { encoding: "utf-8" });
      execSync("git add .workspace && git commit --amend --no-edit", {
        cwd: workspaceDir,
        stdio: "pipe",
      });
    } catch (error) {
      logError(`Failed to create workspace directory: ${error}`);
      return { exitCode: 1 };
    }
  } else {
    // Directory exists, check if it's already a workspace or a repo
    const gitDir = join(workspaceDir, ".git");
    const workspaceFile = join(workspaceDir, ".workspace");
    const icProjectFile = join(workspaceDir, ".ic_project");

    if (existsSync(workspaceFile) || existsSync(icProjectFile)) {
      logInfo(`Workspace '${workspaceName}' already exists at ${workspaceDir}`);
      return { exitCode: 0 };
    }

    if (existsSync(gitDir)) {
      logError(
        `Directory ${workspaceDir} is a git repository, not a workspace`,
      );
      return { exitCode: 1 };
    }

    logError(
      `Directory ${workspaceDir} exists but is not a workspace or git repo`,
    );
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

    // Format target: truncate to ~/repos/... and highlight last path element
    let displayTarget = target;
    if (target.startsWith(reposDir)) {
      // Show as ~/repos/...
      displayTarget = target.replace(reposDir, "~/repos");
    } else if (target.startsWith(home)) {
      // Show as ~/...
      displayTarget = target.replace(home, "~");
    }

    // Highlight the last path element (basename)
    const lastSlash = displayTarget.lastIndexOf("/");
    const formattedTarget =
      lastSlash >= 0
        ? displayTarget.slice(0, lastSlash + 1) +
          chalk.bold(displayTarget.slice(lastSlash + 1))
        : chalk.bold(displayTarget);

    const marker = isCurrent ? chalk.green(" *current") : "";
    console.log(`${nameCol}  ${formattedTarget}${marker}`);
  }

  return { exitCode: 0 };
}

/**
 * Get repo name from git remote URL or fall back to directory basename
 */
function getRepoName(repoDir: string): string {
  let repoName = basename(repoDir);
  try {
    const remoteUrl = execSync("git remote get-url origin", {
      encoding: "utf-8",
      cwd: repoDir,
    }).trim();

    // Extract repo name from URL
    // Handles: git@github.com:user/repo.git, https://github.com/user/repo, etc.
    const match = remoteUrl.match(/\/([^\/]+?)(\.git)?$/);
    if (match) {
      repoName = match[1];
    }
  } catch {
    // No remote or error - use directory basename
  }
  return repoName;
}

/**
 * Create or update a symlink for a specific repo
 * Returns true if symlink was created/updated, false if skipped or error
 */
async function createRepoSymlink(
  repoDir: string,
  force: boolean,
): Promise<boolean> {
  const home = homedir();
  const repoName = getRepoName(repoDir);
  const symlinkPath = join(home, repoName);

  // Check if symlink path already exists
  if (existsSync(symlinkPath)) {
    const stats = lstatSync(symlinkPath);

    if (stats.isSymbolicLink()) {
      // It's a symlink, check where it points
      const currentTarget = readlinkSync(symlinkPath);
      let resolvedTarget: string;
      try {
        resolvedTarget = realpathSync(symlinkPath);
      } catch {
        // Broken symlink
        resolvedTarget = currentTarget;
      }

      if (resolvedTarget === repoDir) {
        logInfo(
          `Symlink ~/${repoName} already points to ${repoDir}. Skipping.`,
        );
        return false;
      }

      // Symlink exists but points elsewhere
      if (!force) {
        const response = await prompt(
          `Symlink ~/${repoName} exists pointing to ${currentTarget}. Update to ${repoDir}? [Y/n]`,
          "Y",
        );

        const choice = response.toUpperCase().trim();
        if (choice !== "Y" && choice !== "YES") {
          logInfo("Skipped");
          return false;
        }
      } else {
        logInfo(
          `Updating symlink ~/${repoName} from ${currentTarget} to ${repoDir}...`,
        );
      }

      // Remove old symlink and create new one
      try {
        unlinkSync(symlinkPath);
        symlinkSync(repoDir, symlinkPath);
        logSuccess(`Updated symlink ~/${repoName} -> ${repoDir}`);
        return true;
      } catch (error) {
        logError(`Failed to update symlink: ${error}`);
        return false;
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
      return false;
    }
  }

  // Symlink doesn't exist, create it
  try {
    symlinkSync(repoDir, symlinkPath);
    logSuccess(`Created symlink ~/${repoName} -> ${repoDir}`);
    return true;
  } catch (error) {
    logError(`Failed to create symlink: ${error}`);
    return false;
  }
}

async function symlinkCreateCommand(force: boolean): Promise<CommandResult> {
  const currentDir = process.cwd();

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

  await createRepoSymlink(gitRoot, force);
  return { exitCode: 0 };
}

interface SymlinkAction {
  repoDir: string;
  repoName: string;
  symlinkPath: string;
  action: "create" | "update" | "skip" | "error" | "warning";
  currentTarget?: string;
  errorMessage?: string;
  warningMessage?: string;
}

/**
 * Check what action would be needed for a symlink without creating it
 */
function checkSymlinkAction(repoDir: string): SymlinkAction {
  const home = homedir();
  const repoName = getRepoName(repoDir);
  const symlinkPath = join(home, repoName);

  // Check if symlink path already exists
  if (existsSync(symlinkPath)) {
    const stats = lstatSync(symlinkPath);

    if (stats.isSymbolicLink()) {
      // It's a symlink, check where it points
      const currentTarget = readlinkSync(symlinkPath);
      let resolvedTarget: string;
      try {
        resolvedTarget = realpathSync(symlinkPath);
      } catch {
        // Broken symlink
        resolvedTarget = currentTarget;
      }

      if (resolvedTarget === repoDir) {
        return {
          repoDir,
          repoName,
          symlinkPath,
          action: "skip",
          currentTarget: resolvedTarget,
        };
      }

      // Symlink exists but points elsewhere
      return {
        repoDir,
        repoName,
        symlinkPath,
        action: "update",
        currentTarget: resolvedTarget,
      };
    }

    // It's a regular file or directory
    return {
      repoDir,
      repoName,
      symlinkPath,
      action: "error",
      errorMessage: `~/${repoName} exists as a regular ${
        stats.isDirectory() ? "directory" : "file"
      }, not a symlink`,
    };
  }

  // Symlink doesn't exist, will create it
  return {
    repoDir,
    repoName,
    symlinkPath,
    action: "create",
  };
}

/**
 * Execute a symlink action (create or update)
 */
function executeSymlinkAction(action: SymlinkAction): boolean {
  try {
    if (action.action === "update") {
      // Remove old symlink
      unlinkSync(action.symlinkPath);
    }
    // Create new symlink
    symlinkSync(action.repoDir, action.symlinkPath);
    return true;
  } catch (error) {
    logError(`Failed to ${action.action} symlink: ${error}`);
    return false;
  }
}

async function symlinkProjectCommand(force: boolean): Promise<CommandResult> {
  const currentDir = process.cwd();
  const workspace = detectWorkspace(currentDir);

  if (!workspace) {
    logError("Not in a project/workspace");
    logError(
      "The 'ic symlink --project' command must be run from within a project directory",
    );
    return { exitCode: 1 };
  }

  const reposDir = getReposDir();
  const projectDir = join(reposDir, workspace);

  logInfo(`Scanning repos in project '${workspace}'...`);

  // Find all git repositories in the project directory
  let items: string[];
  try {
    items = readdirSync(projectDir);
  } catch (error) {
    logError(`Failed to read project directory ${projectDir}: ${error}`);
    return { exitCode: 1 };
  }

  const repos: string[] = [];
  for (const item of items) {
    const itemPath = join(projectDir, item);
    const gitDir = join(itemPath, ".git");

    try {
      const stats = lstatSync(itemPath);
      if (stats.isDirectory() && existsSync(gitDir)) {
        repos.push(itemPath);
      }
    } catch {
      // Skip items we can't read
    }
  }

  if (repos.length === 0) {
    logInfo(`No git repositories found in project '${workspace}'`);
    return { exitCode: 0 };
  }

  // Check what actions are needed for each repo
  const actions: SymlinkAction[] = repos.map((repoDir) =>
    checkSymlinkAction(repoDir),
  );

  // Categorize actions
  const toCreate = actions.filter((a) => a.action === "create");
  const toUpdate = actions.filter((a) => a.action === "update");
  const toSkip = actions.filter((a) => a.action === "skip");
  const errors = actions.filter((a) => a.action === "error");

  // Display planned changes
  console.log();
  logInfo(`Found ${repos.length} repositories in project '${workspace}'`);
  console.log();

  if (toCreate.length > 0) {
    console.log(chalk.bold("Will create:"));
    for (const action of toCreate) {
      console.log(
        `  ${chalk.green("+")} ~/${action.repoName} -> ${action.repoDir}`,
      );
    }
    console.log();
  }

  if (toUpdate.length > 0) {
    console.log(chalk.bold("Will update:"));
    for (const action of toUpdate) {
      console.log(`  ${chalk.yellow("~")} ~/${action.repoName}`);
      console.log(`    ${chalk.dim("from:")} ${action.currentTarget}`);
      console.log(`    ${chalk.dim("to:")}   ${action.repoDir}`);
    }
    console.log();
  }

  if (toSkip.length > 0) {
    console.log(chalk.bold("Already correct (will skip):"));
    for (const action of toSkip) {
      console.log(
        `  ${chalk.dim("=")} ~/${action.repoName} -> ${action.repoDir}`,
      );
    }
    console.log();
  }

  if (errors.length > 0) {
    console.log(chalk.bold.red("Errors (cannot create):"));
    for (const action of errors) {
      console.log(
        `  ${chalk.red("✗")} ~/${action.repoName}: ${action.errorMessage}`,
      );
    }
    console.log();
  }

  const totalChanges = toCreate.length + toUpdate.length;

  if (totalChanges === 0) {
    if (errors.length > 0) {
      logError("No symlinks can be created due to errors above");
      return { exitCode: 1 };
    }
    logInfo("All symlinks are already correct. Nothing to do.");
    return { exitCode: 0 };
  }

  // Ask for confirmation unless --force
  if (!force) {
    const response = await prompt(
      `Create/update ${totalChanges} symlink(s)? [Y/n]`,
      "Y",
    );

    const choice = response.toUpperCase().trim();
    if (choice === "N" || choice === "NO") {
      logInfo("Aborted");
      return { exitCode: 0 };
    }
  }

  // Execute all actions
  console.log();
  logInfo("Creating/updating symlinks...");

  let successCount = 0;
  const actionsToExecute = [...toCreate, ...toUpdate];

  for (const action of actionsToExecute) {
    const success = executeSymlinkAction(action);
    if (success) {
      successCount++;
      if (action.action === "create") {
        logSuccess(`Created ~/${action.repoName} -> ${action.repoDir}`);
      } else {
        logSuccess(`Updated ~/${action.repoName} -> ${action.repoDir}`);
      }
    }
  }

  console.log();
  logSuccess(
    `Completed: ${successCount}/${totalChanges} symlink(s) ${
      force ? "created/updated" : "processed"
    }`,
  );

  if (errors.length > 0) {
    console.log(
      chalk.yellow(
        `Note: ${errors.length} symlink(s) could not be created due to conflicts`,
      ),
    );
  }

  return { exitCode: 0 };
}

/**
 * Check if a given path is inside a project directory.
 * Returns the project name if it is, null otherwise.
 */
function getProjectFromPath(path: string): string | null {
  const reposDir = getReposDir();

  if (!path.startsWith(reposDir)) {
    return null;
  }

  const relativePath = path.slice(reposDir.length + 1);
  const parts = relativePath.split("/").filter((p) => p.length > 0);

  // Need at least 2 parts for a project repo: <project>/<repo>
  if (parts.length < 2) {
    return null;
  }

  const potentialProject = join(reposDir, parts[0]);

  // Check for project marker files
  const hasProjectMarker =
    existsSync(join(potentialProject, ".ic_project")) ||
    existsSync(join(potentialProject, ".workspace"));

  if (hasProjectMarker) {
    return parts[0];
  }

  // If no marker but no .git directory at that level, assume it's a project
  const gitDir = join(potentialProject, ".git");
  if (!existsSync(gitDir)) {
    return parts[0];
  }

  return null;
}

async function symlinkUnlinkProjectCommand(
  force: boolean,
): Promise<CommandResult> {
  const currentDir = process.cwd();
  const workspace = detectWorkspace(currentDir);
  const reposDir = getReposDir();
  const home = homedir();

  let projectRepos: string[];

  if (workspace) {
    // Inside a project - use current behavior (scan that project's repos)
    const projectDir = join(reposDir, workspace);
    logInfo(`Scanning project repos to unlink from project '${workspace}'...`);

    // Find all git repositories in the project directory
    let items: string[];
    try {
      items = readdirSync(projectDir);
    } catch (error) {
      logError(`Failed to read project directory ${projectDir}: ${error}`);
      return { exitCode: 1 };
    }

    projectRepos = [];
    for (const item of items) {
      const itemPath = join(projectDir, item);
      const gitDir = join(itemPath, ".git");

      try {
        const stats = lstatSync(itemPath);
        if (stats.isDirectory() && existsSync(gitDir)) {
          projectRepos.push(itemPath);
        }
      } catch {
        // Skip items we can't read
      }
    }

    if (projectRepos.length === 0) {
      logInfo(`No git repositories found in project '${workspace}'`);
      return { exitCode: 0 };
    }
  } else {
    // Outside a project - scan all symlinks in home directory
    logInfo("Scanning all symlinks for project repos to unlink...");

    // Get all symlinks in home directory
    let homeItems: string[];
    try {
      homeItems = readdirSync(home);
    } catch (error) {
      logError(`Failed to read home directory: ${error}`);
      return { exitCode: 1 };
    }

    projectRepos = [];
    for (const item of homeItems) {
      const itemPath = join(home, item);

      try {
        const stats = lstatSync(itemPath);
        if (!stats.isSymbolicLink()) {
          continue;
        }

        // Get the resolved target
        let target: string;
        try {
          target = realpathSync(itemPath);
        } catch {
          // Broken symlink, skip
          continue;
        }

        // Check if target is inside a project
        const project = getProjectFromPath(target);
        if (project) {
          projectRepos.push(target);
        }
      } catch {
        // Skip items we can't read
      }
    }

    if (projectRepos.length === 0) {
      logInfo("No symlinks found pointing to project repos");
      return { exitCode: 0 };
    }
  }

  // Check what actions are needed for each repo
  const actions: SymlinkAction[] = [];

  for (const projectRepoDir of projectRepos) {
    const repoName = getRepoName(projectRepoDir);
    const symlinkPath = join(home, repoName);
    const globalRepoDir = join(reposDir, repoName);

    // Check if symlink exists and points to project repo
    if (!existsSync(symlinkPath)) {
      // No symlink exists, skip
      continue;
    }

    const stats = lstatSync(symlinkPath);
    if (!stats.isSymbolicLink()) {
      // Not a symlink, skip
      continue;
    }

    let currentTarget: string;
    try {
      currentTarget = realpathSync(symlinkPath);
    } catch {
      // Broken symlink, skip
      continue;
    }

    // Only process if symlink currently points to project repo
    if (currentTarget !== projectRepoDir) {
      // Symlink doesn't point to project repo, skip
      continue;
    }

    // Check if global version exists
    if (!existsSync(globalRepoDir)) {
      actions.push({
        repoDir: globalRepoDir,
        repoName,
        symlinkPath,
        action: "warning",
        currentTarget,
        warningMessage: `Global version ~/repos/${repoName} does not exist`,
      });
      continue;
    }

    // Check if global version is a git repo
    const globalGitDir = join(globalRepoDir, ".git");
    if (!existsSync(globalGitDir)) {
      actions.push({
        repoDir: globalRepoDir,
        repoName,
        symlinkPath,
        action: "warning",
        currentTarget,
        warningMessage: `~/repos/${repoName} exists but is not a git repository`,
      });
      continue;
    }

    // Can update symlink to point to global version
    actions.push({
      repoDir: globalRepoDir,
      repoName,
      symlinkPath,
      action: "update",
      currentTarget,
    });
  }

  if (actions.length === 0) {
    logInfo("No project symlinks found to unlink");
    return { exitCode: 0 };
  }

  // Categorize actions
  const toUpdate = actions.filter((a) => a.action === "update");
  const warnings = actions.filter((a) => a.action === "warning");

  // Display planned changes
  console.log();
  if (workspace) {
    logInfo(
      `Found ${actions.length} symlink(s) pointing to project '${workspace}'`,
    );
  } else {
    logInfo(`Found ${actions.length} symlink(s) pointing to project repos`);
  }
  console.log();

  if (toUpdate.length > 0) {
    console.log(chalk.bold("Will unlink (point to global repos):"));
    for (const action of toUpdate) {
      console.log(`  ${chalk.yellow("~")} ~/${action.repoName}`);
      console.log(`    ${chalk.dim("from:")} ${action.currentTarget}`);
      console.log(`    ${chalk.dim("to:")}   ${action.repoDir}`);
    }
    console.log();
  }

  if (warnings.length > 0) {
    console.log(chalk.bold.yellow("Warnings (cannot unlink):"));
    for (const action of warnings) {
      console.log(
        `  ${chalk.yellow("!")} ~/${action.repoName}: ${action.warningMessage}`,
      );
      console.log(`    ${chalk.dim("currently:")} ${action.currentTarget}`);
    }
    console.log();
  }

  if (toUpdate.length === 0) {
    logError(
      "No symlinks can be unlinked. All project repos lack global counterparts.",
    );
    return { exitCode: 1 };
  }

  // Ask for confirmation unless --force
  if (!force) {
    const response = await prompt(
      `Unlink ${toUpdate.length} symlink(s) from project? [Y/n]`,
      "Y",
    );

    const choice = response.toUpperCase().trim();
    if (choice === "N" || choice === "NO") {
      logInfo("Aborted");
      return { exitCode: 0 };
    }
  }

  // Execute all actions
  console.log();
  logInfo("Unlinking symlinks from project...");

  let successCount = 0;

  for (const action of toUpdate) {
    const success = executeSymlinkAction(action);
    if (success) {
      successCount++;
      logSuccess(`Updated ~/${action.repoName} -> ${action.repoDir}`);
    }
  }

  console.log();
  logSuccess(
    `Completed: ${successCount}/${toUpdate.length} symlink(s) unlinked from project`,
  );

  if (warnings.length > 0) {
    console.log(
      chalk.yellow(
        `Note: ${warnings.length} symlink(s) could not be unlinked (no global version exists)`,
      ),
    );
  }

  return { exitCode: 0 };
}

async function tmuxRenumberCommand(dryRun: boolean): Promise<CommandResult> {
  // Check if in tmux
  if (!process.env.TMUX) {
    logError("Not in a tmux session");
    return { exitCode: 1 };
  }

  // Get current session info to detect if we're in nested tmux
  let sessionName: string;
  let windowName = "";
  let paneTitle = "";
  try {
    const tmuxInfo = execSync(
      'tmux display-message -p "#{session_name}|#{pane_title}|#{window_name}"',
      {
        encoding: "utf-8",
      },
    ).trim();

    [sessionName, paneTitle, windowName] = tmuxInfo.split("|");
  } catch {
    logError("Failed to get current tmux session information");
    return { exitCode: 1 };
  }

  // Detect nested tmux by checking window/pane titles
  const isNested =
    windowName.startsWith("nt:") ||
    windowName.startsWith("ic:") ||
    paneTitle.startsWith("nt:") ||
    paneTitle.startsWith("ic:") ||
    paneTitle.includes("Nested TM");

  // Get list of windows with their indices
  let windowListOutput: string;
  try {
    if (isNested) {
      windowListOutput = execNestedTmux(
        'list-windows -t "${sessionName}" -F "#{window_index}:#{window_name}"',
        { encoding: "utf-8" },
      ) as string;
    } else {
      windowListOutput = execSync(
        `tmux list-windows -t "${sessionName}" -F "#{window_index}:#{window_name}"`,
        { encoding: "utf-8" },
      ) as string;
    }
  } catch (error) {
    logError(`Failed to list windows: ${error}`);
    return { exitCode: 1 };
  }

  // Parse window indices
  const windows = windowListOutput
    .trim()
    .split("\n")
    .map((line) => {
      const [indexStr, name] = line.split(":");
      return { index: parseInt(indexStr, 10), name };
    })
    .sort((a, b) => a.index - b.index);

  if (windows.length === 0) {
    logInfo("No windows found in current session");
    return { exitCode: 0 };
  }

  // Check if renumbering is needed
  let needsRenumbering = false;
  const renumberOps: Array<{
    oldIndex: number;
    newIndex: number;
    name: string;
  }> = [];

  for (let i = 0; i < windows.length; i++) {
    if (windows[i].index !== i) {
      needsRenumbering = true;
      renumberOps.push({
        oldIndex: windows[i].index,
        newIndex: i,
        name: windows[i].name,
      });
    }
  }

  if (!needsRenumbering) {
    logInfo(
      "Windows are already numbered sequentially (0,1,2,...). No action needed.",
    );
    return { exitCode: 0 };
  }

  // Display what will be done
  console.log();
  logInfo(
    `Session '${sessionName}' ${isNested ? "(nested)" : ""} has ${
      windows.length
    } windows with gaps:`,
  );
  console.log();

  console.log(chalk.bold("Current window indices:"));
  console.log(`  ${windows.map((w) => w.index).join(", ")}`);
  console.log();

  console.log(chalk.bold("Will renumber to:"));
  for (const op of renumberOps) {
    console.log(
      `  Window ${chalk.yellow(op.oldIndex.toString())} (${
        op.name
      }) -> ${chalk.green(op.newIndex.toString())}`,
    );
  }
  console.log();

  if (dryRun) {
    logInfo("Dry run complete. Use without --dry-run to apply changes.");
    return { exitCode: 0 };
  }

  // Execute renumbering using tmux's built-in move-window -r command
  try {
    if (isNested) {
      execNestedTmux(`move-window -r -t "${sessionName}"`, { stdio: "pipe" });
    } else {
      execSync(`tmux move-window -r -t "${sessionName}"`, { stdio: "pipe" });
    }
    logSuccess(`Renumbered ${renumberOps.length} window(s)`);
  } catch (error) {
    logError(`Failed to renumber windows: ${error}`);
    return { exitCode: 1 };
  }

  return { exitCode: 0 };
}

async function attachDirsCommand(
  targetDir?: string,
  includeDotdirs = false,
): Promise<CommandResult> {
  // Check if in tmux
  if (!process.env.TMUX) {
    logError("Not in a tmux session");
    return { exitCode: 1 };
  }

  // Get the target directory (default to current directory)
  const dir = targetDir || process.cwd();

  // Check if directory exists
  if (!existsSync(dir)) {
    logError(`Directory does not exist: ${dir}`);
    return { exitCode: 1 };
  }

  // Get current session name
  let sessionName: string;
  try {
    sessionName = execSync('tmux display-message -p "#{session_name}"', {
      encoding: "utf-8",
    }).trim();
  } catch {
    logError("Failed to get current tmux session name");
    return { exitCode: 1 };
  }

  logInfo(`Creating windows for subdirectories in: ${dir}`);

  // Get all subdirectories
  let items: string[];
  try {
    items = readdirSync(dir);
  } catch (error) {
    logError(`Failed to read directory ${dir}: ${error}`);
    return { exitCode: 1 };
  }

  const subdirs: string[] = [];
  for (const item of items) {
    // Skip dot-prefixed directories unless --include-dotdirs is set
    if (!includeDotdirs && item.startsWith(".")) {
      continue;
    }

    const itemPath = join(dir, item);
    try {
      const stats = lstatSync(itemPath);
      if (stats.isDirectory()) {
        subdirs.push(itemPath);
      }
    } catch {
      // Skip items we can't read
    }
  }

  if (subdirs.length === 0) {
    logInfo(`No subdirectories found in ${dir}`);
    return { exitCode: 0 };
  }

  logInfo(`Found ${subdirs.length} subdirectories`);

  // Create a window for each subdirectory
  let successCount = 0;
  for (const subdirPath of subdirs) {
    const windowName = basename(subdirPath);

    try {
      execSync(
        `tmux new-window -t "${sessionName}" -n "${windowName}" -c "${subdirPath}"`,
        {
          stdio: "pipe",
        },
      );
      logSuccess(`Created window '${windowName}' in ${subdirPath}`);
      successCount++;
    } catch (error) {
      logError(`Failed to create window for ${windowName}: ${error}`);
    }
  }

  console.log();
  logSuccess(
    `Created ${successCount}/${subdirs.length} windows in session '${sessionName}'`,
  );

  return { exitCode: 0 };
}

async function main() {
  const args = hideBin(process.argv);

  const argv = await yargs(args)
    .scriptName("ic")
    .usage("$0 <command> [options]")
    .example("$0 c user/repo", "Clone a GitHub repo")
    .example("$0 a", "Attach to nested tmux session")
    .example("$0 s", "Show repo symlinks")
    .epilog(
      "Note: When running 'ic clone' from within a project directory, the repo will be automatically cloned into that project.",
    )
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
          .option("project", {
            alias: "p",
            type: "string",
            description: "Clone into a project directory",
          })
          .option("workspace", {
            alias: "w",
            type: "string",
            description:
              "Clone into a workspace directory (alias for --project)",
          })
          .example("$0 c user/repo", "Clone git@github.com:user/repo.git")
          .example(
            "$0 c myrepo",
            "Clone git@github.com:instacart/myrepo.git (defaults to instacart)",
          )
          .example(
            "$0 c myrepo -p myFeature",
            "Clone into ~/repos/myFeature/myrepo",
          )
          .example("$0 c https://github.com/user/repo", "Clone from HTTPS URL");
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
          })
          .example("$0 a", "Attach to nested tmux (create if needed)")
          .example("$0 a --force", "Detach other clients and attach");
      },
    )
    .command(
      ["attach-dirs [dir]", "ad [dir]"],
      "Create tmux window for each subdirectory",
      (yargs) => {
        return yargs
          .positional("dir", {
            describe:
              "Directory to scan for subdirectories (defaults to current directory)",
            type: "string",
          })
          .option("include-dotdirs", {
            type: "boolean",
            description:
              "Include dot-prefixed directories (like .git, .vscode)",
            default: false,
          })
          .example(
            "$0 ad",
            "Create windows for all subdirectories in current dir",
          )
          .example(
            "$0 ad ~/repos/myproject",
            "Create windows for all subdirectories in specified dir",
          )
          .example(
            "$0 ad --include-dotdirs",
            "Include dot-prefixed directories like .git",
          );
      },
    )
    .command(["tmux", "t"], "Tmux window management", (yargs) => {
      return yargs
        .command(
          ["renumber", "rn"],
          "Renumber tmux windows to remove gaps (0,1,2,3...)",
          (yargs) => {
            return yargs
              .option("dry-run", {
                type: "boolean",
                description: "Show what would be done without making changes",
                default: false,
              })
              .example("$0 t rn", "Renumber windows to 0,1,2,3...")
              .example("$0 t rn --dry-run", "Show what would be renumbered")
              .example("$0 tmux renumber", "Full command to renumber windows");
          },
        )
        .demandCommand(1, "");
    })
    .command(
      ["workspace start [name]", "ws start [name]"],
      "Create a new workspace directory",
      (yargs) => {
        return yargs
          .positional("name", {
            describe: "Workspace name",
            type: "string",
          })
          .example(
            "$0 ws start myFeature",
            "Create workspace ~/repos/myFeature",
          );
      },
    )
    .command(["symlink", "s"], "Manage symlinks for current repo", (yargs) => {
      return yargs
        .command(["show", "$0"], "Show repo symlinks", (yargs) => {
          return yargs
            .option("all", {
              type: "boolean",
              description: "Show all symlinks in home directory",
              default: false,
            })
            .example("$0 s", "Show symlinks pointing to repos")
            .example("$0 s --all", "Show all symlinks in home directory");
        })
        .command(
          ["create", "c"],
          "Create symlink for current repo",
          (yargs) => {
            return yargs
              .option("force", {
                alias: "f",
                type: "boolean",
                description: "Skip confirmation prompts",
                default: false,
              })
              .example("$0 s c", "Create ~/myrepo -> /path/to/myrepo symlink")
              .example("$0 s c -f", "Update symlink without confirmation");
          },
        )
        .command(
          ["project", "p"],
          "Create symlinks for all repos in current project",
          (yargs) => {
            return yargs
              .option("force", {
                alias: "f",
                type: "boolean",
                description: "Skip confirmation prompts",
                default: false,
              })
              .example(
                "$0 s p",
                "Create symlinks for all repos in current project",
              )
              .example(
                "$0 s p -f",
                "Create project symlinks without confirmation",
              );
          },
        )
        .command(
          ["unlink-project", "up"],
          "Unlink project repos, point symlinks back to global repos",
          (yargs) => {
            return yargs
              .option("force", {
                alias: "f",
                type: "boolean",
                description: "Skip confirmation prompts",
                default: false,
              })
              .example(
                "$0 s up",
                "Unlink project, point symlinks to ~/repos/{repo}",
              )
              .example(
                "$0 s up (outside project)",
                "Unlink ALL project symlinks to global repos",
              )
              .example("$0 s up -f", "Unlink without confirmation");
          },
        )
        .demandCommand(1, "");
    })
    .demandCommand(1, "You must provide a command")
    .recommendCommands()
    .strict()
    .help()
    .alias("help", "h")
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
    // Prefer --project over --workspace for backward compatibility
    const projectOrWorkspace =
      (argv.project as string | undefined) ||
      (argv.workspace as string | undefined);
    result = await cloneCommand(argv.repo as string, projectOrWorkspace);
  } else if (command === "attach" || command === "a") {
    result = await attachCommand(argv.force as boolean, argv.cwd as boolean);
  } else if (command === "attach-dirs" || command === "ad") {
    result = await attachDirsCommand(
      argv.dir as string | undefined,
      argv["include-dotdirs"] as boolean,
    );
  } else if (command === "tmux" || command === "t") {
    // Subcommand is in argv._[1]
    const tmuxSubcommand = subcommand;

    if (tmuxSubcommand === "renumber" || tmuxSubcommand === "rn") {
      result = await tmuxRenumberCommand(argv["dry-run"] as boolean);
    } else {
      logError(`Unknown tmux subcommand: ${tmuxSubcommand}`);
      logError("Available subcommands: renumber (rn)");
      result = { exitCode: 1 };
    }
  } else if (
    (command === "workspace" || command === "ws") &&
    subcommand === "start"
  ) {
    result = await workspaceStartCommand(argv.name as string | undefined);
  } else if (command === "symlink" || command === "s") {
    // Subcommand is in argv._[1], defaults to 'show' via yargs $0
    const symlinkSubcommand = subcommand || "show";

    if (symlinkSubcommand === "show") {
      result = await symlinkShowCommand(argv.all as boolean);
    } else if (symlinkSubcommand === "create" || symlinkSubcommand === "c") {
      result = await symlinkCreateCommand(argv.force as boolean);
    } else if (symlinkSubcommand === "project" || symlinkSubcommand === "p") {
      result = await symlinkProjectCommand(argv.force as boolean);
    } else if (
      symlinkSubcommand === "unlink-project" ||
      symlinkSubcommand === "up"
    ) {
      result = await symlinkUnlinkProjectCommand(argv.force as boolean);
    } else {
      logError(`Unknown symlink subcommand: ${symlinkSubcommand}`);
      logError("Available subcommands: show, create, project, unlink-project");
      result = { exitCode: 1 };
    }
  } else {
    // This should never happen due to .demandCommand(), but just in case
    logError("Unknown command");
    result = { exitCode: 1 };
  }

  process.exit(result.exitCode);
}

// Only run main if this is the entry point (not imported)
// Use realpathSync to handle symlinks and macOS /private prefix
function isEntryPoint(): boolean {
  try {
    // In compiled Bun executables, import.meta.url includes $bunfs
    // which means we're in a compiled binary and should run
    if (import.meta.url.includes("$bunfs")) {
      return true;
    }

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
