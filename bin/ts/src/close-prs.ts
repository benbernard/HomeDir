#!/usr/bin/env tsx

import chalk from "chalk";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import { $ } from "zx";
import {
  logDebug,
  logError,
  logInfo,
  logSuccess,
  logWarning,
} from "./lib/logger";
import { confirmAction } from "./lib/prompts";

$.verbose = false;

interface ClosePRsOptions {
  repo?: string;
  draftOnly: boolean;
  olderThan: number;
  author?: string;
  base?: string;
  label?: string;
  message?: string;
  dryRun: boolean;
  yes: boolean;
  verbose: boolean;
  limit: number;
}

interface PRInfo {
  number: number;
  title: string;
  author: string;
  isDraft: boolean;
  createdAt: string;
  updatedAt: string;
  headRefName: string;
  baseRefName: string;
  url: string;
}

function formatAge(dateString: string): string {
  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

  if (diffDays === 0) {
    const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
    if (diffHours === 0) {
      const diffMinutes = Math.floor(diffMs / (1000 * 60));
      return `${diffMinutes}m ago`;
    }
    return `${diffHours}h ago`;
  }
  if (diffDays === 1) return "1 day ago";
  if (diffDays < 7) return `${diffDays} days ago`;
  if (diffDays < 30) {
    const weeks = Math.floor(diffDays / 7);
    return `${weeks} week${weeks > 1 ? "s" : ""} ago`;
  }
  if (diffDays < 365) {
    const months = Math.floor(diffDays / 30);
    return `${months} month${months > 1 ? "s" : ""} ago`;
  }
  const years = Math.floor(diffDays / 365);
  return `${years} year${years > 1 ? "s" : ""} ago`;
}

function getDaysOld(dateString: string): number {
  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now.getTime() - date.getTime();
  return Math.floor(diffMs / (1000 * 60 * 60 * 24));
}

function truncate(str: string, maxLen: number): string {
  if (str.length <= maxLen) return str;
  return `${str.slice(0, maxLen - 3)}...`;
}

async function getCurrentRepo(): Promise<string | null> {
  try {
    const result = await $`gh repo view --json nameWithOwner -q .nameWithOwner`;
    return result.stdout.trim();
  } catch {
    return null;
  }
}

async function listOpenPRs(options: ClosePRsOptions): Promise<PRInfo[]> {
  const repoArg = options.repo ? ["--repo", options.repo] : [];
  const allPRs: PRInfo[] = [];
  const batchSize = 100; // gh CLI fetches efficiently in batches
  let fetched = 0;

  // Fetch PRs in batches using cursor-based pagination
  while (fetched < options.limit) {
    const remaining = options.limit - fetched;
    const fetchCount = Math.min(batchSize, remaining);

    // Build the gh search query
    const searchArgs = [
      "pr",
      "list",
      ...repoArg,
      "--state",
      "open",
      "--json",
      "number,title,author,isDraft,createdAt,updatedAt,headRefName,baseRefName,url",
      "--limit",
      String(fetchCount),
    ];

    // Add base branch filter if specified
    if (options.base) {
      searchArgs.push("--base", options.base);
    }

    // Add author filter if specified
    if (options.author) {
      searchArgs.push("--author", options.author);
    }

    // Add label filter if specified
    if (options.label) {
      searchArgs.push("--label", options.label);
    }

    // Use --search to paginate by excluding already-fetched PRs
    if (allPRs.length > 0) {
      // gh doesn't have native cursor pagination for pr list,
      // but we can use the fact that results are sorted by created date
      // and filter by created date less than the oldest we've seen
      const oldestPR = allPRs[allPRs.length - 1];
      searchArgs.push("--search", `created:<${oldestPR.createdAt}`);
    }

    logDebug(`Running: gh ${searchArgs.join(" ")}`, options.verbose);

    try {
      const result = await $`gh ${searchArgs}`;
      const prs: Array<{
        number: number;
        title: string;
        author: { login: string };
        isDraft: boolean;
        createdAt: string;
        updatedAt: string;
        headRefName: string;
        baseRefName: string;
        url: string;
      }> = JSON.parse(result.stdout);

      if (prs.length === 0) {
        // No more PRs to fetch
        break;
      }

      const mappedPRs = prs.map((pr) => ({
        number: pr.number,
        title: pr.title,
        author: pr.author.login,
        isDraft: pr.isDraft,
        createdAt: pr.createdAt,
        updatedAt: pr.updatedAt,
        headRefName: pr.headRefName,
        baseRefName: pr.baseRefName,
        url: pr.url,
      }));

      allPRs.push(...mappedPRs);
      fetched += prs.length;

      logDebug(
        `Fetched ${prs.length} PRs (total: ${allPRs.length})`,
        options.verbose,
      );

      // If we got fewer than requested, we've reached the end
      if (prs.length < fetchCount) {
        break;
      }
    } catch (error) {
      if (error instanceof Error) {
        logError("Failed to list PRs", error.message);
      }
      break;
    }
  }

  return allPRs;
}

function filterPRs(prs: PRInfo[], options: ClosePRsOptions): PRInfo[] {
  return prs.filter((pr) => {
    // Filter by draft status
    if (options.draftOnly && !pr.isDraft) {
      logDebug(`Skipping PR #${pr.number}: not a draft`, options.verbose);
      return false;
    }

    // Filter by age
    const daysOld = getDaysOld(pr.createdAt);
    if (daysOld < options.olderThan) {
      logDebug(
        `Skipping PR #${pr.number}: only ${daysOld} days old (need ${options.olderThan})`,
        options.verbose,
      );
      return false;
    }

    return true;
  });
}

function displayPRs(prs: PRInfo[]): void {
  if (prs.length === 0) {
    logInfo("No PRs found matching the criteria");
    return;
  }

  console.log();
  console.log(chalk.bold(`Found ${prs.length} PR(s) to close:`));
  console.log();

  // Calculate column widths
  const maxNumWidth = Math.max(...prs.map((pr) => String(pr.number).length), 2);
  const maxAuthorWidth = Math.min(
    Math.max(...prs.map((pr) => pr.author.length), 6),
    15,
  );
  const maxTitleWidth = 50;

  // Header
  const header = [
    chalk.gray("#".padStart(maxNumWidth)),
    chalk.gray("Author".padEnd(maxAuthorWidth)),
    chalk.gray("Age".padEnd(12)),
    chalk.gray("Status".padEnd(8)),
    chalk.gray("Title"),
  ].join("  ");
  console.log(header);
  console.log(chalk.gray("-".repeat(header.length + 20)));

  // PRs
  for (const pr of prs) {
    const num = chalk.cyan(`#${pr.number}`.padStart(maxNumWidth + 1));
    const author = chalk.yellow(
      truncate(pr.author, maxAuthorWidth).padEnd(maxAuthorWidth),
    );
    const age = formatAge(pr.createdAt).padEnd(12);
    const status = pr.isDraft
      ? chalk.magenta("draft".padEnd(8))
      : chalk.green("ready".padEnd(8));
    const title = truncate(pr.title, maxTitleWidth);

    console.log(`${num}  ${author}  ${age}  ${status}  ${title}`);
  }

  console.log();
}

async function closePR(
  pr: PRInfo,
  options: ClosePRsOptions,
  current: number,
  total: number,
): Promise<boolean> {
  const repoArg = options.repo ? ["--repo", options.repo] : [];
  const progress = chalk.gray(`[${current}/${total}]`);

  if (options.dryRun) {
    console.log(
      `${progress} ${chalk.gray("Would close")} PR #${pr.number}: ${truncate(
        pr.title,
        50,
      )}`,
    );
    return true;
  }

  try {
    // Close the PR
    const closeArgs = ["pr", "close", String(pr.number), ...repoArg];

    // Add comment if provided
    if (options.message) {
      closeArgs.push("--comment", options.message);
    }

    logDebug(`Running: gh ${closeArgs.join(" ")}`, options.verbose);
    const result = await $`gh ${closeArgs}`.quiet();
    // Print gh output with progress prefix (gh outputs to stderr)
    const output = (result.stdout || result.stderr).trim();
    if (output) {
      console.log(`${progress} ${output}`);
    } else {
      console.log(`${progress} Closed PR #${pr.number}`);
    }
    return true;
  } catch (error) {
    if (error instanceof Error) {
      console.log(
        `${progress} ${chalk.red("✗")} Failed to close PR #${pr.number}: ${
          error.message
        }`,
      );
    }
    return false;
  }
}

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .usage(
      "Close open pull requests in a GitHub repository\n\nUsage: $0 [options]",
    )
    .option("repo", {
      alias: "R",
      type: "string",
      description: "Repository in OWNER/REPO format (defaults to current repo)",
    })
    .option("close-ready", {
      type: "boolean",
      description: "Also close non-draft (ready) PRs (default: draft PRs only)",
      default: false,
    })
    .option("older-than", {
      alias: "o",
      type: "number",
      description: "Only close PRs older than N days",
      default: 30,
    })
    .option("author", {
      alias: "a",
      type: "string",
      description: "Only close PRs by specific author (GitHub username)",
    })
    .option("base", {
      alias: "b",
      type: "string",
      description: "Only close PRs targeting specific base branch",
    })
    .option("label", {
      alias: "L",
      type: "string",
      description: "Only close PRs with specific label",
    })
    .option("message", {
      alias: "m",
      type: "string",
      description: "Add a comment when closing PRs",
    })
    .option("dry-run", {
      alias: "n",
      type: "boolean",
      description: "Preview what would be closed without making changes",
      default: false,
    })
    .option("yes", {
      alias: "y",
      type: "boolean",
      description: "Skip confirmation prompt",
      default: false,
    })
    .option("limit", {
      alias: "l",
      type: "number",
      description: "Maximum number of PRs to fetch (fetches in batches of 100)",
      default: 1000,
    })
    .option("verbose", {
      alias: "v",
      type: "boolean",
      description: "Enable verbose output",
      default: false,
    })
    .example("$0", "Close draft PRs older than 30 days in current repo")
    .example(
      "$0 --close-ready",
      "Close all PRs (including ready) older than 30 days",
    )
    .example("$0 --older-than 60", "Close draft PRs older than 60 days")
    .example("$0 --author octocat", "Close draft PRs by octocat")
    .example(
      "$0 -R owner/repo --dry-run",
      "Preview what would be closed in owner/repo",
    )
    .example('$0 -m "Closing stale PR"', "Close with a comment")
    .help()
    .alias("help", "h")
    .parse();

  const options: ClosePRsOptions = {
    repo: argv.repo,
    draftOnly: !argv["close-ready"],
    olderThan: argv["older-than"],
    author: argv.author,
    base: argv.base,
    label: argv.label,
    message: argv.message,
    dryRun: argv["dry-run"],
    yes: argv.yes,
    verbose: argv.verbose,
    limit: argv.limit,
  };

  // Determine repo
  let repoDisplay: string | undefined = options.repo;
  if (!repoDisplay) {
    repoDisplay = (await getCurrentRepo()) ?? undefined;
    if (!repoDisplay) {
      logError("Could not determine repository. Use --repo to specify.");
      process.exit(1);
    }
  }

  if (options.dryRun) {
    logWarning("DRY RUN MODE - No PRs will be closed");
  }

  // Display filter criteria
  console.log(chalk.bold(`\nRepository: ${chalk.cyan(repoDisplay)}`));
  console.log(chalk.gray("Filters:"));
  console.log(
    chalk.gray(
      `  • Status: ${
        options.draftOnly ? "draft only" : "all (including ready)"
      }`,
    ),
  );
  console.log(chalk.gray(`  • Age: older than ${options.olderThan} days`));
  if (options.author) {
    console.log(chalk.gray(`  • Author: ${options.author}`));
  }
  if (options.base) {
    console.log(chalk.gray(`  • Base branch: ${options.base}`));
  }
  if (options.label) {
    console.log(chalk.gray(`  • Label: ${options.label}`));
  }

  // Fetch PRs
  logInfo("Fetching open PRs...");
  const allPRs = await listOpenPRs(options);
  logDebug(`Fetched ${allPRs.length} open PRs`, options.verbose);

  // Filter PRs
  const prsToClose = filterPRs(allPRs, options);

  if (prsToClose.length === 0) {
    logSuccess("No PRs match the criteria. Nothing to do.");
    process.exit(0);
  }

  // Display PRs
  displayPRs(prsToClose);

  // Confirm
  if (!options.yes && !options.dryRun) {
    const confirmed = await confirmAction(`Close ${prsToClose.length} PR(s)?`);
    if (!confirmed) {
      logInfo("Cancelled by user");
      process.exit(0);
    }
  }

  // Close PRs
  console.log();
  logInfo(options.dryRun ? "Would close the following PRs:" : "Closing PRs...");
  console.log();

  let closedCount = 0;
  let failedCount = 0;
  const total = prsToClose.length;

  for (let i = 0; i < prsToClose.length; i++) {
    const pr = prsToClose[i];
    const success = await closePR(pr, options, i + 1, total);
    if (success) {
      closedCount++;
    } else {
      failedCount++;
    }
  }

  // Summary
  console.log();
  if (options.dryRun) {
    logSuccess(`Would have closed ${closedCount} PR(s)`);
  } else {
    if (closedCount > 0) {
      logSuccess(`Closed ${closedCount} PR(s)`);
    }
    if (failedCount > 0) {
      logWarning(`Failed to close ${failedCount} PR(s)`);
    }
  }

  process.exit(failedCount > 0 ? 1 : 0);
}

main();
