#!/usr/bin/env node

import { execSync, spawnSync } from "child_process";
import { existsSync, readdirSync } from "fs";
import { homedir } from "os";
import { basename, dirname, join } from "path";
import chalk from "chalk";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

interface CommandResult {
  action?: "cd";
  path?: string;
  exitCode: number;
}

interface GitWorktree {
  path: string;
  branch: string;
  bare: boolean;
}

function logError(message: string): void {
  console.error(`${chalk.red("Error:")} ${message}`);
}

function logInfo(message: string): void {
  console.log(`${chalk.blue("→")} ${message}`);
}

function logSuccess(message: string): void {
  console.log(`${chalk.green("✓")} ${message}`);
}

function logWarning(message: string): void {
  console.log(`${chalk.yellow("!")} ${message}`);
}

function logDebug(message: string, verbose: boolean): void {
  if (verbose) {
    console.log(`${chalk.gray("DEBUG:")} ${message}`);
  }
}

function execGit(args: string[], cwd?: string, silent = false): string {
  try {
    return execSync(`git ${args.join(" ")}`, {
      cwd: cwd || process.cwd(),
      encoding: "utf-8",
      stdio: silent ? "pipe" : ["pipe", "pipe", "pipe"],
    }).trim();
  } catch (error) {
    if (!silent) throw error;
    return "";
  }
}

function execGitWithStatus(
  args: string[],
  cwd?: string,
): { stdout: string; stderr: string; status: number } {
  const result = spawnSync("git", args, {
    cwd: cwd || process.cwd(),
    encoding: "utf-8",
  });
  return {
    stdout: result.stdout || "",
    stderr: result.stderr || "",
    status: result.status || 0,
  };
}

function getWorktrees(gitDir?: string): GitWorktree[] {
  const cwd = gitDir || process.cwd();
  const output = execGit(["worktree", "list", "--porcelain"], cwd);
  const worktrees: GitWorktree[] = [];

  let current: Partial<GitWorktree> = {};

  for (const line of output.split("\n")) {
    if (line.startsWith("worktree ")) {
      current.path = line.substring(9);
    } else if (line === "bare") {
      current.bare = true;
    } else if (line.startsWith("branch ")) {
      const branch = line.substring(7);
      current.branch = branch.replace(/^refs\/heads\//, "");
    } else if (line === "") {
      if (current.path) {
        worktrees.push({
          path: current.path,
          branch: current.branch || "",
          bare: current.bare || false,
        });
      }
      current = {};
    }
  }

  // Handle last entry if no trailing newline
  if (current.path) {
    worktrees.push({
      path: current.path,
      branch: current.branch || "",
      bare: current.bare || false,
    });
  }

  return worktrees;
}

function getGitCommonDir(): string | null {
  try {
    return execGit(["rev-parse", "--git-common-dir"], undefined, true);
  } catch {
    return null;
  }
}

function getGitDir(): string | null {
  try {
    return execGit(["rev-parse", "--absolute-git-dir"], undefined, true);
  } catch {
    return null;
  }
}

function isWorktreeSetup(verbose: boolean): boolean {
  const gitDir = getGitDir();
  const gitCommonDir = getGitCommonDir();

  if (!gitDir || !gitCommonDir) {
    return false;
  }

  logDebug(`git_dir=${gitDir}`, verbose);
  logDebug(`git_common_dir=${gitCommonDir}`, verbose);
  logDebug(`Are they equal? ${gitDir === gitCommonDir}`, verbose);

  const isBare = existsSync(join(gitCommonDir, "config"))
    ? execSync(
        `grep "bare = true" "${join(
          gitCommonDir,
          "config",
        )}" 2>/dev/null || echo ""`,
        {
          encoding: "utf-8",
        },
      ).trim() !== ""
    : false;

  logDebug(`Is bare? ${isBare}`, verbose);

  return gitDir !== gitCommonDir || isBare;
}

async function cloneCommand(
  input: string,
  verbose: boolean,
): Promise<CommandResult> {
  if (!input) {
    logError("Usage: wt clone <user/repo> or <repo>");
    console.log("  If no user specified, defaults to 'instacart'");
    return { exitCode: 1 };
  }

  // Parse input
  let user: string;
  let repo: string;

  if (input.includes("/")) {
    const parts = input.split("/");
    user = parts[0];
    repo = parts[1];
  } else {
    user = "instacart";
    repo = input;
  }

  const repoUrl = `git@github.com:${user}/${repo}.git`;
  const reposDir = join(homedir(), "repos");
  let repoDir = join(reposDir, repo);

  // Handle directory collision
  if (existsSync(repoDir)) {
    repoDir = join(reposDir, `${repo}-wt`);
    logInfo(
      `Directory ${join(
        reposDir,
        repo,
      )} already exists, using ${repoDir} instead`,
    );
  }

  const bareDir = join(repoDir, "bare");
  const masterDir = join(repoDir, "master");

  // Create repo directory
  execSync(`mkdir -p "${repoDir}"`, { stdio: "inherit" });

  // Clone as bare repository
  logInfo(`Cloning ${repoUrl} as bare repository to ${bareDir}...`);
  try {
    execSync(`git clone --bare "${repoUrl}" "${bareDir}"`, {
      stdio: "inherit",
    });
  } catch {
    logError("Failed to clone repository");
    return { exitCode: 1 };
  }

  // Configure fetch refspec
  logInfo("Configuring remote fetch refspec...");
  execGit(
    ["config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"],
    bareDir,
  );

  // Create master worktree
  logInfo(`Creating master worktree at ${masterDir}...`);
  let result = execGitWithStatus(
    ["worktree", "add", "../master", "master"],
    bareDir,
  );

  if (result.status !== 0) {
    result = execGitWithStatus(
      ["worktree", "add", "../master", "main"],
      bareDir,
    );
  }

  if (result.status === 0) {
    logSuccess("Successfully created worktree structure:");
    console.log(`  Bare repo: ${bareDir}`);
    console.log(`  Master worktree: ${masterDir}`);
    return { action: "cd", path: masterDir, exitCode: 0 };
  }

  logError("Failed to create master worktree");
  return { exitCode: 1 };
}

async function createBranchCommand(
  branchName: string,
  baseBranch: string | undefined,
  verbose: boolean,
): Promise<CommandResult> {
  if (!branchName) {
    logError("Usage: wt -b <branch-name> [base-branch]");
    console.log("  Creates a new branch and worktree");
    console.log("  base-branch defaults to current branch if not specified");
    return { exitCode: 1 };
  }

  const gitCommonDir = getGitCommonDir();
  if (!gitCommonDir) {
    logError("Not in a git repository");
    return { exitCode: 1 };
  }

  if (!isWorktreeSetup(verbose)) {
    logWarning("Not in a worktree environment!");
    console.log(
      "You're in a regular git repository. Consider using 'wt clone' to set up worktrees.",
    );
    console.log("");
    console.log("Current setup: Regular repository");
    console.log(
      "Worktree setup: Clone with 'wt clone <repo>' to enable worktrees",
    );
    return { exitCode: 1 };
  }

  // Get current branch if not specified
  let base = baseBranch;
  if (!base) {
    base = execGit(["branch", "--show-current"], undefined, true);
    logInfo(`Using current branch '${base}' as base`);
  }

  // Ensure fetch refspec is configured
  const fetchRefspec = execGit(
    ["config", "--get", "remote.origin.fetch"],
    undefined,
    true,
  );
  if (fetchRefspec !== "+refs/heads/*:refs/remotes/origin/*") {
    logDebug("Configuring fetch refspec for remote.origin", verbose);
    execGit(
      ["config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"],
      undefined,
      true,
    );
  }

  // Fetch from origin
  logInfo("Fetching from origin to update remote tracking branches...");
  try {
    execSync("git fetch origin", { stdio: "inherit" });
  } catch {
    logWarning("Failed to fetch from origin. Continuing anyway...");
  }

  // Determine worktree parent directory
  let worktreeParentDir = gitCommonDir;
  if (basename(gitCommonDir) === "bare") {
    worktreeParentDir = dirname(gitCommonDir);
    logDebug(
      `Detected 'bare' subdir, creating worktree in parent: ${worktreeParentDir}`,
      verbose,
    );
  } else {
    logDebug(
      `Using old-style structure, creating worktree in git dir: ${worktreeParentDir}`,
      verbose,
    );
  }

  const worktreeDir = join(worktreeParentDir, branchName);
  logDebug(`Will create worktree at: ${worktreeDir}`, verbose);

  // Check if worktree already exists
  if (existsSync(worktreeDir)) {
    logInfo(`Worktree '${branchName}' already exists, switching to it...`);
    return { action: "cd", path: worktreeDir, exitCode: 0 };
  }

  // Check if branch already exists
  const branchExists =
    execGit(["rev-parse", "--verify", branchName], undefined, true) !== "";

  if (branchExists) {
    logInfo(
      `Branch '${branchName}' already exists. Checking out existing branch in new worktree...`,
    );
    execSync(`git worktree add "${worktreeDir}" "${branchName}"`, {
      stdio: "inherit",
    });
  } else {
    logInfo(`Creating new branch '${branchName}' from '${base}'...`);
    execSync(`git worktree add -b "${branchName}" "${worktreeDir}" "${base}"`, {
      stdio: "inherit",
    });
  }

  logSuccess(`Successfully created worktree at ${worktreeDir}`);
  return { action: "cd", path: worktreeDir, exitCode: 0 };
}

async function listCommand(): Promise<CommandResult> {
  execSync("git worktree list", { stdio: "inherit" });
  return { exitCode: 0 };
}

async function removeCommand(
  worktreePath: string | undefined,
): Promise<CommandResult> {
  let path = worktreePath;

  if (!path) {
    path = process.cwd();
    logInfo(`Removing current worktree: ${path}`);
  }

  // Check if in git repo
  try {
    execGit(["rev-parse", "--git-dir"], undefined, true);
  } catch {
    logError("Not in a git repository");
    return { exitCode: 1 };
  }

  // Check for uncommitted changes
  try {
    execSync("git diff-index --quiet HEAD --", { stdio: "pipe" });
  } catch {
    logError("Cannot remove worktree with uncommitted changes");
    console.log("Please commit or stash your changes first");
    console.log("");
    console.log("Uncommitted changes:");
    execSync("git status --short", { stdio: "inherit" });
    return { exitCode: 1 };
  }

  // Check for untracked files
  const untrackedFiles = execGit(
    ["ls-files", "--others", "--exclude-standard"],
    undefined,
    true,
  );
  if (untrackedFiles) {
    logWarning("Worktree has untracked files");
    console.log(untrackedFiles);
    // Note: In TypeScript/Node, we can't easily do interactive prompts like zsh's read
    // You might want to add a --force flag or use a library like 'prompts'
    logError(
      "Cannot remove worktree with untracked files (use --force to override)",
    );
    return { exitCode: 1 };
  }

  execSync(`git worktree remove "${path}"`, { stdio: "inherit" });
  return { exitCode: 0 };
}

async function interactiveCommand(verbose: boolean): Promise<CommandResult> {
  logDebug("Interactive mode triggered", verbose);

  // Check if fzf is available
  try {
    execSync("command -v fzf", { stdio: "pipe" });
  } catch {
    logError("fzf is not installed");
    return { exitCode: 1 };
  }

  logDebug("fzf found", verbose);

  const gitCommonDir = getGitCommonDir();
  if (!gitCommonDir) {
    logError("Not in a git repository");
    return { exitCode: 1 };
  }

  logDebug(`git_dir=${gitCommonDir}`, verbose);

  const worktrees = getWorktrees(gitCommonDir);

  if (verbose) {
    console.log("DEBUG: Worktrees:");
    for (const wt of worktrees) {
      console.log(`  ${wt.branch} -> ${wt.path} (bare: ${wt.bare})`);
    }
  }

  // Format for fzf display
  const formatted = worktrees
    .filter((wt) => !wt.bare)
    .map((wt) => {
      const branch = wt.branch.padEnd(20);
      return `${branch} ${wt.path}`;
    })
    .join("\n");

  if (verbose) {
    console.log("DEBUG: Formatted worktrees:");
    console.log(formatted);
  }

  // Create preview script
  const preview = `
    wt_path=$(echo {} | awk '{print $NF}')
    wt_branch=$(echo {} | awk '{print $1}')
    echo "Branch: $wt_branch"
    echo "Path: $wt_path"
    echo ""
    cd "$wt_path" && git log --color --pretty=format:'%C(red)%h%Creset %C(magenta)%ar%Creset %C(yellow)%an%Creset %Cgreen%s%Creset %C(cyan)%d%Creset' -10
  `;

  try {
    const result = spawnSync(
      "fzf",
      ["--header=Select worktree to switch to", `--preview=${preview}`],
      {
        input: formatted,
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "inherit"],
      },
    );

    const selected = result.stdout.trim();
    logDebug(`selected=${selected}`, verbose);

    if (selected) {
      const targetPath = selected.split(/\s+/).pop();
      if (targetPath) {
        logDebug(`Changing to ${targetPath}`, verbose);
        return { action: "cd", path: targetPath, exitCode: 0 };
      }
    }
  } catch (error) {
    logError(`Failed to run fzf: ${error}`);
    return { exitCode: 1 };
  }

  return { exitCode: 0 };
}

function showHelp(): void {
  console.log("Git Worktree Manager");
  console.log("");
  console.log("Usage:");
  console.log(
    "  wt [--verbose]                  Interactive worktree selector (fzf)",
  );
  console.log(
    "  wt clone <user/repo>            Clone repo to ~/repos and create master worktree",
  );
  console.log(
    "  wt clone <repo>                 Clone instacart/<repo> to ~/repos",
  );
  console.log(
    "  wt -b <branch> [base]           Create new branch and worktree (base defaults to current)",
  );
  console.log("  wt list|ls                      List all worktrees");
  console.log(
    "  wt remove|rm [path]             Remove a worktree (defaults to current directory)",
  );
  console.log("  wt --help|-h|help               Show this help message");
  console.log("");
  console.log("Options:");
  console.log("  --verbose, -v                   Show debug output");
  console.log("");
  console.log("Directory Structure:");
  console.log("  ~/repos/myrepo/");
  console.log("    ├── bare/                     Bare git repository");
  console.log("    ├── master/                   Master worktree");
  console.log("    └── feature-branch/           Other worktrees");
  console.log("");
  console.log("Examples:");
  console.log(
    "  wt clone user/repo              # Clone git@github.com:user/repo.git",
  );
  console.log(
    "  wt clone myrepo                 # Clone git@github.com:instacart/myrepo.git",
  );
  console.log("  wt -b feature-123               # Create from current branch");
  console.log("  wt -b feature-123 main          # Create from main branch");
  console.log(
    "  wt remove                       # Remove current worktree (checks for uncommitted changes)",
  );
  console.log("  wt remove /path/to/worktree     # Remove specific worktree");
  console.log(
    "  wt --verbose                    # Show debug output in interactive mode",
  );
}

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .option("verbose", {
      alias: "v",
      type: "boolean",
      description: "Show debug output",
      default: false,
    })
    .command(
      "clone <repo>",
      "Clone a GitHub repo and create master worktree",
      (yargs) => {
        return yargs.positional("repo", {
          describe:
            "Repository in format user/repo or just repo (defaults to instacart)",
          type: "string",
        });
      },
    )
    .command(
      "-b <branch> [base]",
      "Create new branch and worktree",
      (yargs) => {
        return yargs
          .positional("branch", {
            describe: "New branch name",
            type: "string",
          })
          .positional("base", {
            describe: "Base branch (defaults to current)",
            type: "string",
          });
      },
    )
    .command(["list", "ls"], "List all worktrees")
    .command(["remove [path]", "rm [path]"], "Remove a worktree", (yargs) => {
      return yargs.positional("path", {
        describe: "Path to worktree (defaults to current directory)",
        type: "string",
      });
    })
    .command(["help", "--help", "-h"], "Show help message")
    .help(false)
    .version(false)
    .parse();

  const verbose = argv.verbose as boolean;
  const command = argv._[0] as string | undefined;

  let result: CommandResult;

  if (command === "clone") {
    result = await cloneCommand(argv.repo as string, verbose);
  } else if (command === "-b") {
    result = await createBranchCommand(
      argv.branch as string,
      argv.base as string | undefined,
      verbose,
    );
  } else if (command === "list" || command === "ls") {
    result = await listCommand();
  } else if (command === "remove" || command === "rm") {
    result = await removeCommand(argv.path as string | undefined);
  } else if (command === "help" || argv.help) {
    showHelp();
    result = { exitCode: 0 };
  } else if (!command) {
    // Interactive mode
    result = await interactiveCommand(verbose);
  } else {
    logError(`Unknown subcommand: ${command}`);
    console.log("Run 'wt --help' for usage information");
    result = { exitCode: 1 };
  }

  // Output result for shell wrapper
  if (result.action === "cd" && result.path) {
    console.log(`__WT_CD__${result.path}`);
  }

  process.exit(result.exitCode);
}

main().catch((error) => {
  logError(`Unexpected error: ${error}`);
  process.exit(1);
});
