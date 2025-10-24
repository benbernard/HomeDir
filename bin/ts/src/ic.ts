#!/usr/bin/env node

import { execSync } from "child_process";
import { appendFileSync, existsSync, readdirSync } from "fs";
import { homedir } from "os";
import { basename, join } from "path";
import * as readline from "readline";
import chalk from "chalk";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

interface CommandResult {
  exitCode: number;
}

let shellCommandExchangeFile: string | undefined;

function logError(message: string): void {
  console.error(`${chalk.red("Error:")} ${message}`);
}

function logInfo(message: string): void {
  console.log(`${chalk.blue("→")} ${message}`);
}

function logSuccess(message: string): void {
  console.log(`${chalk.green("✓")} ${message}`);
}

function outputCommand(cmd: string): void {
  if (shellCommandExchangeFile) {
    // Write to file as JSON
    appendFileSync(
      shellCommandExchangeFile,
      `${JSON.stringify({ run: cmd })}\n`,
    );
  } else {
    // Print in human-readable format for debugging
    console.log(`Would run: ${cmd}`);
  }
}

function prompt(question: string, defaultValue?: string): Promise<string> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });

  return new Promise((resolve) => {
    const promptText = defaultValue
      ? `${question} [${defaultValue}]: `
      : `${question}: `;

    rl.question(promptText, (answer) => {
      rl.close();
      resolve(answer.trim() || defaultValue || "");
    });
  });
}

async function cloneCommand(input: string): Promise<CommandResult> {
  if (!input) {
    logError("Usage: ic clone <user/repo> or <repo>");
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
    // Just repo name provided, default to instacart
    user = "instacart";
    repo = input;
  }

  const repoUrl = `git@github.com:${user}/${repo}.git`;
  const reposDir = join(homedir(), "repos");
  let repoDir = join(reposDir, repo);

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

  logSuccess(`Successfully cloned to ${repoDir}`);
  outputCommand(`cd "${repoDir}"`);
  return { exitCode: 0 };
}

async function attachCommand(
  force: boolean,
  resume: boolean,
): Promise<CommandResult> {
  // Check if in tmux
  if (!process.env.TMUX) {
    logError("Not in a tmux session");
    return { exitCode: 1 };
  }

  // Check if already in a nested tmux session (detect ic_ prefix in current session)
  try {
    const currentSession = execSync(
      'tmux display-message -p "#{session_name}"',
      {
        encoding: "utf-8",
      },
    ).trim();

    if (currentSession.startsWith("ic_")) {
      logError(
        `Already in a nested tmux session '${currentSession}'. Detach first.`,
      );
      return { exitCode: 1 };
    }
  } catch {
    // Ignore errors, continue
  }

  // Get repo root
  let repoRoot: string;
  try {
    repoRoot = execSync("git rev-parse --show-toplevel", {
      encoding: "utf-8",
    }).trim();
  } catch {
    logError("Not in a git repository");
    return { exitCode: 1 };
  }

  // Verify repo is under ~/repos
  const reposDir = join(homedir(), "repos");
  if (!repoRoot.startsWith(reposDir)) {
    logError("Must be in a repo under ~/repos");
    return { exitCode: 1 };
  }

  // Extract repo directory name and create session name
  // Use underscore instead of colon because tmux converts colons to underscores
  const repoDirName = basename(repoRoot);
  const sessionName = `ic_${repoDirName}`;

  // Check if session already exists
  let sessionExists = false;
  try {
    execSync(`tmux has-session -t "${sessionName}" 2>&1`, {
      stdio: "pipe",
    });
    sessionExists = true;
  } catch {
    sessionExists = false;
  }

  // Handle --resume flag
  if (resume) {
    if (!sessionExists) {
      logError(
        `Session '${sessionName}' does not exist. Use 'ic a' without --resume to create it.`,
      );
      return { exitCode: 1 };
    }

    // Check if another client is attached
    try {
      const clients = execSync(`tmux list-clients -t "${sessionName}" 2>&1`, {
        encoding: "utf-8",
      }).trim();

      if (clients) {
        logError(
          `Session '${sessionName}' is already attached by another client.`,
        );
        logInfo("Active clients:");
        console.log(clients);
        return { exitCode: 1 };
      }
    } catch {
      // No clients attached, which is what we want
    }

    logInfo(`Resuming session '${sessionName}'...`);

    // Just attach to existing session, don't create windows
    const resumeScript = [
      `printf '\\033knt: ${sessionName}\\033\\\\'`,
      `TMUX= exec tmux attach-session -t "${sessionName}"`,
    ].join("\n");

    const resumeCommand = `tmpscript=$(mktemp) && cat > "$tmpscript" << 'ICEOF'\n${resumeScript}\nICEOF\ntmux new-window -n "${sessionName}" -c "${repoRoot}" "zsh $tmpscript; rm -f $tmpscript"`;

    outputCommand(resumeCommand);

    return { exitCode: 0 };
  }

  // Normal attach behavior (not --resume)
  if (sessionExists) {
    if (!force) {
      logError(
        `Session '${sessionName}' already exists. Use --force to recreate or --resume to attach.`,
      );
      return { exitCode: 1 };
    }
    logInfo(`Session '${sessionName}' exists, attaching with --force...`);
  } else {
    logInfo(`Creating new session '${sessionName}'...`);
  }

  // Create a single command that sets up a new outer tmux window with nested session
  // Use a temp script approach to avoid complex quote escaping
  const scriptCommands = [
    `TMUX= tmux new-session -d -s "${sessionName}" -c "${repoRoot}" 2>/dev/null`,
    `TMUX= tmux new-window -t "${sessionName}:1" -c "${repoRoot}"`,
    `TMUX= tmux new-window -t "${sessionName}:2" -c "${repoRoot}"`,
    `TMUX= tmux select-window -t "${sessionName}:0"`,
    `printf '\\033knt: ${sessionName}\\033\\\\'`,
    `TMUX= exec tmux attach-session -t "${sessionName}"`,
  ].join("\n");

  // Create the command that writes a temp script and executes it
  const setupCommand = `tmpscript=$(mktemp) && cat > "$tmpscript" << 'ICEOF'\n${scriptCommands}\nICEOF\ntmux new-window -n "${sessionName}" -c "${repoRoot}" "zsh $tmpscript; rm -f $tmpscript"`;

  outputCommand(setupCommand);

  return { exitCode: 0 };
}

function showHelp(): void {
  console.log("IC - Simple Git Clone & Attach Manager");
  console.log("");
  console.log("Usage:");
  console.log(
    "  ic clone|c <user/repo>          Clone repo to ~/repos with SSH",
  );
  console.log(
    "  ic clone|c <repo>               Clone repo (defaults to instacart/<repo>)",
  );
  console.log(
    "  ic attach|a [--force]           Create/attach nested tmux session",
  );
  console.log(
    "  ic attach|a --resume            Resume existing session (fail if attached)",
  );
  console.log("  ic --help|-h|help               Show this help message");
  console.log("");
  console.log("Examples:");
  console.log(
    "  ic c user/repo                  # Clone git@github.com:user/repo.git",
  );
  console.log(
    "  ic c myrepo                     # Clone git@github.com:instacart/myrepo.git",
  );
  console.log(
    "  ic a                            # Create nested tmux (3 windows)",
  );
  console.log("  ic a --resume                   # Resume existing session");
  console.log(
    "  ic a --force                    # Recreate session even if exists",
  );
}

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .option("shell-command-exchange", {
      type: "string",
      description: "File path for shell command exchange",
      hidden: true,
    })
    .command(
      ["clone <repo>", "c <repo>"],
      "Clone a GitHub repo with SSH",
      (yargs) => {
        return yargs.positional("repo", {
          describe: "Repository in format user/repo or just repo",
          type: "string",
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
            description: "Recreate session even if it exists",
            default: false,
          })
          .option("resume", {
            type: "boolean",
            description:
              "Resume existing session (fail if not exists or attached)",
            default: false,
          });
      },
    )
    .command(["help", "--help", "-h"], "Show help message")
    .help(false)
    .version(false)
    .parse();

  // Set the shell command exchange file if provided
  shellCommandExchangeFile = argv["shell-command-exchange"] as
    | string
    | undefined;

  const command = argv._[0] as string | undefined;

  let result: CommandResult;

  if (command === "clone" || command === "c") {
    result = await cloneCommand(argv.repo as string);
  } else if (command === "attach" || command === "a") {
    result = await attachCommand(argv.force as boolean, argv.resume as boolean);
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

main().catch((error) => {
  logError(`Unexpected error: ${error}`);
  process.exit(1);
});
