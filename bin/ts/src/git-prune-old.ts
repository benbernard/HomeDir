#!/usr/bin/env tsx

import { execSync, spawnSync } from "child_process";
import * as readline from "readline";
import chalk from "chalk";
import { DateTime } from "luxon";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

interface PruneOptions {
  dryRun: boolean;
  force: boolean;
  days: number;
  mainBranch?: string | null;
  remote: string;
  deleteRemote: boolean;
  verbose: boolean;
}

interface BranchCommitInfo {
  name: string;
  lastCommitDate: DateTime;
  lastCommitMessage: string;
  lastCommitAuthor: string;
  localSha: string;
  remoteSha: string | null;
  daysOld: number;
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

function execGit(args: string[], silent = false): string {
  try {
    return execSync(`git ${args.join(" ")}`, {
      encoding: "utf-8",
      stdio: silent ? "pipe" : ["pipe", "pipe", "pipe"],
    }).trim();
  } catch (error) {
    if (!silent) throw error;
    return "";
  }
}

function execGitSafe(args: string[]): {
  stdout: string;
  stderr: string;
  status: number;
} {
  const result = spawnSync("git", args, {
    encoding: "utf-8",
  });
  return {
    stdout: (result.stdout || "").trim(),
    stderr: (result.stderr || "").trim(),
    status: result.status || 0,
  };
}

function getCurrentBranch(): string | null {
  // Try modern git command first
  const result = execGitSafe(["branch", "--show-current"]);
  if (result.status === 0 && result.stdout) {
    return result.stdout;
  }

  // Fallback for detached HEAD or older git
  const symbolicRef = execGitSafe(["symbolic-ref", "--short", "-q", "HEAD"]);
  if (symbolicRef.status === 0 && symbolicRef.stdout) {
    return symbolicRef.stdout;
  }

  return null;
}

function getDefaultBranch(remote: string): string {
  // Try to get the default branch from remote HEAD
  const result = execGitSafe(["symbolic-ref", `refs/remotes/${remote}/HEAD`]);
  if (result.status === 0 && result.stdout) {
    return result.stdout.replace(`refs/remotes/${remote}/`, "");
  }

  // Fallback: check git config
  const configResult = execGitSafe(["config", "--get", "init.defaultBranch"]);
  if (configResult.status === 0 && configResult.stdout) {
    return configResult.stdout;
  }

  // Final fallback: use 'main' if it exists, otherwise 'master'
  const branches = execGitSafe(["branch", "--list", "main", "master"]);
  if (branches.stdout.includes("main")) {
    return "main";
  }

  return "master";
}

function remoteExists(remote: string): boolean {
  const result = execGitSafe(["remote", "get-url", remote]);
  return result.status === 0;
}

function isWorkingTreeDirty(): boolean {
  const result = execGitSafe(["diff", "--quiet", "HEAD"]);
  return result.status !== 0;
}

function stashChanges(): boolean {
  logWarning("Found a dirty working tree, stashing");
  const result = execGitSafe([
    "stash",
    "push",
    "-m",
    "git-prune-old auto-stash",
  ]);
  return result.status === 0;
}

function popStash(): boolean {
  logInfo("Restoring working tree from stash");
  const result = execGitSafe(["stash", "pop"]);
  if (result.status !== 0) {
    logError(
      "Failed to restore stash. You may need to run 'git stash pop' manually.",
    );
    return false;
  }
  return true;
}

function fetchRemote(remote: string): boolean {
  logInfo(`Fetching from ${remote}`);
  const result = execGitSafe(["fetch", remote, "--prune"]);
  if (result.status !== 0) {
    logError(`Failed to fetch from ${remote}: ${result.stderr}`);
    return false;
  }
  return true;
}

function checkoutBranch(branch: string): boolean {
  logInfo(`Checking out ${branch}`);
  const result = execGitSafe(["checkout", branch]);
  if (result.status !== 0) {
    logError(`Failed to checkout ${branch}: ${result.stderr}`);
    return false;
  }
  return true;
}

function deleteLocalBranch(branch: string, dryRun: boolean): boolean {
  if (dryRun) {
    console.log(`Would delete local branch: ${chalk.yellow(branch)}`);
    return true;
  }

  logInfo(`Deleting local branch: ${branch}`);
  const result = execGitSafe(["branch", "-D", branch]);
  if (result.status !== 0) {
    logError(`Failed to delete local branch ${branch}: ${result.stderr}`);
    return false;
  }
  return true;
}

function deleteRemoteBranch(
  remote: string,
  branch: string,
  dryRun: boolean,
): boolean {
  if (dryRun) {
    console.log(
      `Would delete remote branch: ${chalk.yellow(`${remote}/${branch}`)}`,
    );
    return true;
  }

  logInfo(`Deleting remote branch: ${remote}/${branch}`);
  const result = execGitSafe(["push", remote, "--delete", branch]);
  if (result.status !== 0) {
    logError(
      `Failed to delete remote branch ${remote}/${branch}: ${result.stderr}`,
    );
    return false;
  }
  return true;
}

function getLocalBranches(): string[] {
  const result = execGitSafe([
    "for-each-ref",
    "--format=%(refname:short)",
    "refs/heads/",
  ]);

  if (result.status !== 0) {
    return [];
  }

  return result.stdout
    .split("\n")
    .map((b) => b.trim())
    .filter((b) => b);
}

function getBranchLastCommitInfo(
  branch: string,
  remote: string,
): BranchCommitInfo | null {
  // Get last commit info for the branch
  const result = execGitSafe([
    "log",
    "-1",
    "--format=%H%n%at%n%s%n%an",
    branch,
  ]);

  if (result.status !== 0 || !result.stdout) {
    return null;
  }

  const lines = result.stdout.split("\n");
  if (lines.length < 4) {
    return null;
  }

  const [sha, timestamp, message, author] = lines;
  const commitDate = DateTime.fromSeconds(Number.parseInt(timestamp, 10));
  const now = DateTime.now();
  const daysOld = Math.floor(now.diff(commitDate, "days").days);

  // Get remote SHA if it exists
  const remoteShaResult = execGitSafe(["rev-parse", `${remote}/${branch}`]);
  const remoteSha =
    remoteShaResult.status === 0 ? remoteShaResult.stdout : null;

  return {
    name: branch,
    lastCommitDate: commitDate,
    lastCommitMessage: message,
    lastCommitAuthor: author,
    localSha: sha,
    remoteSha,
    daysOld,
  };
}

function getOldBranches(
  daysThreshold: number,
  mainBranch: string,
  currentBranch: string | null,
  remote: string,
  verbose: boolean,
): BranchCommitInfo[] {
  logDebug(`Finding branches older than ${daysThreshold} days`, verbose);

  const branches = getLocalBranches();
  const oldBranches: BranchCommitInfo[] = [];

  for (const branch of branches) {
    // Skip main branch and current branch
    if (branch === mainBranch || branch === currentBranch) {
      logDebug(`Skipping ${branch} (protected)`, verbose);
      continue;
    }

    const info = getBranchLastCommitInfo(branch, remote);
    if (!info) {
      logDebug(`Could not get info for ${branch}`, verbose);
      continue;
    }

    if (info.daysOld >= daysThreshold) {
      oldBranches.push(info);
    }
  }

  // Sort by age (oldest first)
  oldBranches.sort((a, b) => b.daysOld - a.daysOld);

  return oldBranches;
}

function truncateString(str: string, maxLength: number): string {
  if (str.length <= maxLength) {
    return str;
  }
  return `${str.slice(0, maxLength - 3)}...`;
}

function displayBranchTable(branches: BranchCommitInfo[]): void {
  console.log("\nBranches to delete:\n");

  // Calculate column widths
  const maxNameLength = Math.max(15, ...branches.map((b) => b.name.length));
  const maxAuthorLength = Math.max(
    12,
    ...branches.map((b) => b.lastCommitAuthor.length),
  );

  // Header
  const nameHeader = "Branch".padEnd(maxNameLength);
  const daysHeader = "Days".padStart(5);
  const dateHeader = "Last Commit".padEnd(19);
  const authorHeader = "Author".padEnd(maxAuthorLength);
  const messageHeader = "Message";

  console.log(
    chalk.gray(
      `${nameHeader}  ${daysHeader}  ${dateHeader}  ${authorHeader}  ${messageHeader}`,
    ),
  );
  console.log(chalk.gray("-".repeat(maxNameLength + maxAuthorLength + 80)));

  // Rows
  for (const branch of branches) {
    const name = chalk.cyan(branch.name.padEnd(maxNameLength));
    const days = chalk.yellow(branch.daysOld.toString().padStart(5));
    const date = branch.lastCommitDate.toFormat("yyyy-MM-dd HH:mm").padEnd(19);
    const author = truncateString(
      branch.lastCommitAuthor,
      maxAuthorLength,
    ).padEnd(maxAuthorLength);
    const message = truncateString(branch.lastCommitMessage, 40);

    // Add sync indicator
    const inSync = branch.remoteSha === branch.localSha;
    const syncIndicator = branch.remoteSha
      ? inSync
        ? chalk.green("✓")
        : chalk.yellow("⚠")
      : chalk.gray("○");

    console.log(
      `${name}  ${days}  ${date}  ${author}  ${message} ${syncIndicator}`,
    );
  }

  console.log();
  console.log(
    `${chalk.green("✓")} = in sync with remote, ${chalk.yellow(
      "⚠",
    )} = out of sync, ${chalk.gray("○")} = no remote branch`,
  );
  console.log();
}

async function confirmAction(message: string): Promise<boolean> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    rl.question(`${chalk.yellow("?")} ${message} (y/N): `, (answer) => {
      rl.close();
      resolve(answer.toLowerCase() === "y" || answer.toLowerCase() === "yes");
    });
  });
}

async function pruneBranches(options: PruneOptions): Promise<number> {
  // Disable OVERCOMMIT
  process.env.OVERCOMMIT_DISABLE = "1";

  const { dryRun, force, days, remote, deleteRemote, verbose } = options;

  if (dryRun) {
    logWarning("DRY RUN MODE - No changes will be made");
  }

  // Get or detect main branch
  const mainBranch = options.mainBranch || getDefaultBranch(remote);
  logDebug(`Using main branch: ${mainBranch}`, verbose);

  // Check if remote exists
  if (!remoteExists(remote)) {
    logError(`Remote '${remote}' does not exist`);
    return 1;
  }

  // Save current state
  const currentBranch = getCurrentBranch();
  const startingBranch = currentBranch;
  logDebug(`Current branch: ${currentBranch || "detached"}`, verbose);

  const isDirty = isWorkingTreeDirty();
  let stashed = false;

  if (isDirty && !dryRun) {
    if (!stashChanges()) {
      logError("Failed to stash changes");
      return 1;
    }
    stashed = true;
  }

  try {
    // Switch to main branch if not already there
    if (currentBranch !== mainBranch) {
      if (!dryRun && !checkoutBranch(mainBranch)) {
        return 1;
      }
      if (dryRun) {
        logInfo(`Would checkout ${mainBranch}`);
      }
    }

    // Fetch from remote
    if (!dryRun && !fetchRemote(remote)) {
      return 1;
    }
    if (dryRun) {
      logInfo(`Would fetch from ${remote} with --prune`);
    }

    // Get old branches
    const oldBranches = getOldBranches(
      days,
      mainBranch,
      currentBranch,
      remote,
      verbose,
    );

    if (oldBranches.length === 0) {
      logSuccess(`No branches older than ${days} days`);
      return 0;
    }

    logInfo(`Found ${oldBranches.length} branch(es) older than ${days} days`);

    // Filter out starting branch if we stashed changes
    const branchesToDelete = stashed
      ? oldBranches.filter((b) => b.name !== startingBranch)
      : oldBranches;

    if (stashed && oldBranches.length !== branchesToDelete.length) {
      logWarning(
        `Excluding starting branch '${startingBranch}' from deletion (working tree was stashed)`,
      );
    }

    if (branchesToDelete.length === 0) {
      logSuccess("No branches to delete after applying filters");
      return 0;
    }

    // Display branches
    displayBranchTable(branchesToDelete);

    // Confirm if not forced
    if (!force && !dryRun) {
      const deleteMsg = deleteRemote
        ? `Delete ${branchesToDelete.length} branch(es) locally and remotely?`
        : `Delete ${branchesToDelete.length} local branch(es)?`;
      const confirmed = await confirmAction(deleteMsg);
      if (!confirmed) {
        logInfo("Cancelled by user");
        return 0;
      }
    }

    // Delete branches
    for (const branch of branchesToDelete) {
      const inSync = branch.remoteSha === branch.localSha;

      // Delete local branch
      if (!deleteLocalBranch(branch.name, dryRun)) {
        logWarning(`Skipping remote deletion for ${branch.name}`);
        continue;
      }

      // Delete remote branch if requested and exists
      if (deleteRemote && branch.remoteSha) {
        if (inSync) {
          deleteRemoteBranch(remote, branch.name, dryRun);
        } else {
          logWarning(
            `Not deleting remote branch ${remote}/${branch.name} - out of sync with local`,
          );
        }
      }
    }

    if (!dryRun) {
      logSuccess(`Cleaned up ${branchesToDelete.length} branch(es)`);
    }

    // Restore original branch
    if (currentBranch && currentBranch !== mainBranch) {
      // Check if the branch still exists before trying to check it out
      const branchExists = getLocalBranches().includes(currentBranch);
      if (branchExists) {
        if (!dryRun && !checkoutBranch(currentBranch)) {
          logWarning(`Failed to return to ${currentBranch}`);
        }
        if (dryRun) {
          logInfo(`Would checkout ${currentBranch}`);
        }
      } else {
        logWarning(
          `Original branch ${currentBranch} was deleted, staying on ${mainBranch}`,
        );
      }
    }

    return 0;
  } finally {
    // Always try to restore stash
    if (stashed && !dryRun) {
      popStash();
    }
  }
}

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .usage("Usage: $0 [options]")
    .option("days", {
      alias: "d",
      type: "number",
      description: "Delete branches older than this many days",
      default: 30,
    })
    .option("dry-run", {
      alias: "n",
      type: "boolean",
      description: "Preview what would be deleted without making changes",
      default: false,
    })
    .option("force", {
      alias: "f",
      type: "boolean",
      description: "Skip confirmation prompts",
      default: false,
    })
    .option("main-branch", {
      alias: "m",
      type: "string",
      description: "Specify the main branch (auto-detected if not provided)",
    })
    .option("remote", {
      alias: "r",
      type: "string",
      description: "Specify the remote to use",
      default: "origin",
    })
    .option("no-delete-remote", {
      type: "boolean",
      description: "Only delete local branches, not remote branches",
      default: false,
    })
    .option("verbose", {
      alias: "v",
      type: "boolean",
      description: "Enable verbose output",
      default: false,
    })
    .help()
    .alias("help", "h")
    .example("$0", "Delete local and remote branches older than 30 days")
    .example("$0 --days 60", "Delete branches older than 60 days")
    .example("$0 --dry-run", "Preview what would be deleted")
    .example("$0 --no-delete-remote", "Only delete local branches")
    .parse();

  const options: PruneOptions = {
    dryRun: argv["dry-run"],
    force: argv.force,
    days: argv.days,
    mainBranch: argv["main-branch"],
    remote: argv.remote,
    deleteRemote: !argv["no-delete-remote"],
    verbose: argv.verbose,
  };

  try {
    const exitCode = await pruneBranches(options);
    process.exit(exitCode);
  } catch (error) {
    logError(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}

main();
