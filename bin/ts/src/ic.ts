#!/usr/bin/env node

import { execSync } from "child_process";
import {
  appendFileSync,
  existsSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from "fs";
import { homedir } from "os";
import { basename, join } from "path";
import * as readline from "readline";
import chalk from "chalk";
import { dedent } from "ts-dedent";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

interface CommandResult {
  exitCode: number;
}

interface IcConfig {
  hooks?: Record<string, string[]>;
  autoDetect?: Record<string, string[]>;
}

let shellIntegrationScript: string | undefined;

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

function loadIcConfig(): IcConfig {
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

function detectRepoFiles(repoDir: string): string[] {
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

function resolveSetupHooks(
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

  let repoRoot: string;
  let repoDirName: string;

  if (cwd) {
    // Use current working directory
    repoRoot = process.cwd();
    repoDirName = basename(repoRoot);
  } else {
    // Get repo root
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

    // Extract repo directory name
    repoDirName = basename(repoRoot);
  }

  // Create session name
  // Use underscore instead of colon because tmux converts colons to underscores
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

  if (sessionExists) {
    // Session exists - check if it's attached
    let isAttached = false;
    try {
      const clients = execSync(`tmux list-clients -t "${sessionName}" 2>&1`, {
        encoding: "utf-8",
      }).trim();
      isAttached = clients.length > 0;
    } catch {
      isAttached = false;
    }

    if (isAttached) {
      // Session is attached
      if (force) {
        logInfo(
          `Session '${sessionName}' is attached, detaching other clients...`,
        );
        // Detach all other clients
        try {
          execSync(`tmux detach-client -s "${sessionName}" -a`, {
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

    const attachExistingScript = dedent`
      (
        printf '\\033kic: ${repoDirName}\\033\\\\'
        local TMUX=""
        tmux attach-session -t "${sessionName}"
      )
    `;

    outputScript(attachExistingScript);
    return { exitCode: 0 };
  }

  // Session doesn't exist, create it
  logInfo(`Creating new session '${sessionName}'...`);

  // Create a script that sets up nested tmux session and attaches to it
  const createScript = dedent`
    (
      printf '\\033kic: ${repoDirName}\\033\\\\'
      local TMUX=""
      tmux new-session -d -s "${sessionName}" -c "${repoRoot}"
      tmux new-window -t "${sessionName}:1" -c "${repoRoot}"
      tmux new-window -t "${sessionName}:2" -c "${repoRoot}"
      tmux select-window -t "${sessionName}:0"
      tmux attach-session -t "${sessionName}"
    )
  `;

  outputScript(createScript);

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
    "  ic attach|a [--force] [--cwd]   Attach to nested tmux session (create if needed)",
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
    "  ic a                            # Attach to nested tmux (create if needed)",
  );
  console.log(
    "  ic a --force                    # Detach other clients and attach",
  );
  console.log(
    "  ic a --cwd                      # Attach from current directory (no ~/repos check)",
  );
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
            description: "Detach other clients and attach",
            default: false,
          })
          .option("cwd", {
            type: "boolean",
            description:
              "Use current working directory without requiring ~/repos",
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

  let result: CommandResult;

  if (command === "clone" || command === "c") {
    result = await cloneCommand(argv.repo as string);
  } else if (command === "attach" || command === "a") {
    result = await attachCommand(argv.force as boolean, argv.cwd as boolean);
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
