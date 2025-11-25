#!/usr/bin/env tsx

import chalk from "chalk";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import { execGit, execGitSafe } from "./lib/git";
import {
  logDebug,
  logError,
  logInfo,
  logSuccess,
  logWarning,
} from "./lib/logger";
import { confirmAction } from "./lib/prompts";

interface CleanupOptions {
  dryRun: boolean;
  force: boolean;
  mainBranch?: string | null;
  remote: string;
  deleteRemote: boolean;
  includeGone: boolean;
  verbose: boolean;
}

interface BranchInfo {
  name: string;
  localSha: string;
  remoteSha: string | null;
  isMerged: boolean;
  isGone: boolean;
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

  // Check if we're in detached HEAD state
  const detached = execGitSafe(["branch", "--contains", "HEAD"]);
  if (detached.stdout.includes("* (HEAD detached at")) {
    const match = detached.stdout.match(/\* \(HEAD detached at (\S+)\)/);
    if (match) {
      return match[1];
    }
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
  const result = execGitSafe(["stash", "push", "-m", "git-cleanup auto-stash"]);
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

function getMergedBranches(mainBranch: string, verbose: boolean): string[] {
  logDebug(`Getting branches merged into ${mainBranch}`, verbose);

  const result = execGitSafe([
    "branch",
    "--merged",
    mainBranch,
    "--format=%(refname:short)",
  ]);

  if (result.status !== 0) {
    logError(`Failed to get merged branches: ${result.stderr}`);
    return [];
  }

  return result.stdout
    .split("\n")
    .map((b) => b.trim())
    .filter((b) => b && b !== mainBranch);
}

function getGoneBranches(verbose: boolean): string[] {
  logDebug("Getting branches with deleted remotes (gone)", verbose);

  const result = execGitSafe([
    "for-each-ref",
    "--format=%(refname:short) %(upstream:track)",
    "refs/heads/",
  ]);

  if (result.status !== 0) {
    logError(`Failed to get gone branches: ${result.stderr}`);
    return [];
  }

  return result.stdout
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.includes("[gone]"))
    .map((line) => line.split(" ")[0]);
}

function getBranchSha(branch: string): string {
  const result = execGitSafe(["rev-parse", branch]);
  return result.stdout;
}

function getRemoteBranchSha(remote: string, branch: string): string | null {
  const result = execGitSafe(["rev-parse", `${remote}/${branch}`]);
  if (result.status === 0) {
    return result.stdout;
  }
  return null;
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

function deleteLocalBranch(
  branch: string,
  dryRun: boolean,
  force = false,
): boolean {
  if (dryRun) {
    const forceMsg = force ? " (force)" : "";
    console.log(
      `Would delete local branch: ${chalk.yellow(branch)}${forceMsg}`,
    );
    return true;
  }

  const deleteFlag = force ? "-D" : "-d";
  logInfo(`Deleting local branch: ${branch}${force ? " (force)" : ""}`);
  const result = execGitSafe(["branch", deleteFlag, branch]);
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

function fetchRemote(remote: string): boolean {
  logInfo(`Fetching from ${remote}`);
  const result = execGitSafe(["fetch", remote]);
  if (result.status !== 0) {
    logError(`Failed to fetch from ${remote}: ${result.stderr}`);
    return false;
  }
  return true;
}

function pruneRemote(remote: string, dryRun: boolean): boolean {
  if (dryRun) {
    console.log(`Would prune stale references from: ${chalk.yellow(remote)}`);
    return true;
  }

  logInfo(`Pruning stale references from ${remote}`);
  const result = execGitSafe(["remote", "prune", remote]);
  if (result.status !== 0) {
    logError(`Failed to prune ${remote}: ${result.stderr}`);
    return false;
  }
  return true;
}

async function cleanupBranches(options: CleanupOptions): Promise<number> {
  // Disable OVERCOMMIT (same as original script)
  process.env.OVERCOMMIT_DISABLE = "1";

  const { dryRun, force, remote, deleteRemote, includeGone, verbose } = options;

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
      logInfo(`Would fetch from ${remote}`);
    }

    // Get merged branches and gone branches
    const mergedBranches = getMergedBranches(mainBranch, verbose);
    const goneBranches = includeGone ? getGoneBranches(verbose) : [];

    // Combine branches (avoid duplicates)
    const mergedSet = new Set(mergedBranches);
    const goneSet = new Set(goneBranches);
    const allBranches = [...new Set([...mergedBranches, ...goneBranches])];

    if (allBranches.length === 0) {
      logSuccess("No branches to clean up");
    } else {
      logInfo(
        `Found ${allBranches.length} branch(es) to clean up (${mergedBranches.length} merged, ${goneBranches.length} gone)`,
      );

      // Build list of branches with sync status
      const branchInfos: BranchInfo[] = [];
      for (const branch of allBranches) {
        const localSha = getBranchSha(branch);
        const remoteSha = getRemoteBranchSha(remote, branch);
        const isMerged = mergedSet.has(branch);
        const isGone = goneSet.has(branch);
        branchInfos.push({
          name: branch,
          localSha,
          remoteSha,
          isMerged,
          isGone,
        });
      }

      // Show what will be deleted
      console.log("\nBranches to delete:");
      for (const branch of branchInfos) {
        const inSync = branch.remoteSha === branch.localSha;
        const reasonParts: string[] = [];

        if (branch.isMerged) reasonParts.push(chalk.green("merged"));
        if (branch.isGone) reasonParts.push(chalk.yellow("gone"));

        const syncStatus = branch.remoteSha
          ? inSync
            ? chalk.green("in sync")
            : chalk.yellow("out of sync")
          : "";

        const status = [reasonParts.join(", "), syncStatus]
          .filter(Boolean)
          .join(" - ");
        console.log(`  ${chalk.cyan(branch.name)} - ${status}`);
      }
      console.log();

      // Confirm if not forced
      if (!force && !dryRun) {
        const confirmed = await confirmAction(
          `Delete ${branchInfos.length} branch(es)?`,
        );
        if (!confirmed) {
          logInfo("Cancelled by user");
          return 0;
        }
      }

      // Delete branches
      for (const branch of branchInfos) {
        const inSync = branch.remoteSha === branch.localSha;

        // Delete local branch (force delete if it's a gone branch - squash merged)
        if (!deleteLocalBranch(branch.name, dryRun, branch.isGone)) {
          logWarning(`Skipping remote deletion for ${branch.name}`);
          continue;
        }

        // Delete remote branch if requested and in sync
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
        logSuccess(`Cleaned up ${branchInfos.length} branch(es)`);
      }
    }

    // Prune remote references
    console.log();
    if (!pruneRemote(remote, dryRun)) {
      logWarning(`Failed to prune ${remote}`);
    }

    // Also prune 'team' remote if it exists
    if (remoteExists("team")) {
      if (!pruneRemote("team", dryRun)) {
        logWarning("Failed to prune team");
      }
      if (!dryRun) {
        fetchRemote("team");
      }
    }

    // Restore original branch
    if (currentBranch && currentBranch !== mainBranch) {
      if (!dryRun && !checkoutBranch(currentBranch)) {
        logWarning(`Failed to return to ${currentBranch}`);
      }
      if (dryRun) {
        logInfo(`Would checkout ${currentBranch}`);
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
    .option("include-gone", {
      alias: "g",
      type: "boolean",
      description:
        "Include branches where remote is gone (squash-merged branches)",
      default: true,
    })
    .option("verbose", {
      alias: "v",
      type: "boolean",
      description: "Enable verbose output",
      default: false,
    })
    .help()
    .alias("help", "h")
    .parse();

  const options: CleanupOptions = {
    dryRun: argv["dry-run"],
    force: argv.force,
    mainBranch: argv["main-branch"],
    remote: argv.remote,
    deleteRemote: !argv["no-delete-remote"],
    includeGone: argv["include-gone"],
    verbose: argv.verbose,
  };

  try {
    const exitCode = await cleanupBranches(options);
    process.exit(exitCode);
  } catch (error) {
    logError(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}

main();
