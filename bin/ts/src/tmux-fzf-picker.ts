#!/usr/bin/env tsx

import { chmodSync, writeFileSync } from "fs";
import { homedir, tmpdir } from "os";
import { join } from "path";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

/** Expand $HOME and ~ at the start of a path */
function expandHome(p: string): string {
  const home = homedir();
  if (p === "~" || p.startsWith("~/")) {
    return home + p.slice(1);
  }
  // Replace $HOME or ${HOME} at start of path
  return p.replace(/^(\$HOME\b|\$\{HOME\})/, home);
}

function tempPath(paneId: string, ext: string): string {
  const safe = paneId.replace(/[^a-zA-Z0-9_-]/g, "_");
  return join(tmpdir(), `fzf-picker-${safe}.${ext}`);
}

function shellQuote(s: string): string {
  return `'${s.replace(/'/g, "'\\''")}'`;
}

function handlePick(args: {
  type: "f" | "d";
  dir: string;
  paneId: string;
  showIgnored: boolean;
  exclude: string[];
  noToggles: boolean;
  prefix: string;
}): void {
  const dir = expandHome(args.dir);
  const statePath = tempPath(args.paneId, "state");
  const helperPath = tempPath(args.paneId, "sh");
  const runnerPath = tempPath(args.paneId, "run");

  const excludes =
    args.exclude.length > 0 ? args.exclude : [".git", "node_modules"];
  const hidden = true;
  const showIgnored = args.showIgnored;

  // Write state file (shell-sourceable key=value)
  const stateLines = [
    `type=${args.type}`,
    `hidden=${hidden ? 1 : 0}`,
    `ignore=${showIgnored ? 1 : 0}`,
    `exclude="${excludes.join(" ")}"`,
  ];
  writeFileSync(statePath, `${stateLines.join("\n")}\n`, "utf-8");

  // Write helper script (lightweight — called by fzf reload/transform-header)
  const helperLines = [
    "#!/bin/sh",
    `SF=${shellQuote(statePath)}`,
    '. "$SF"',
    'case "$1" in',
    '  hidden) if [ "$hidden" = 1 ]; then hidden=0; else hidden=1; fi ;;',
    '  ignore) if [ "$ignore" = 1 ]; then ignore=0; else ignore=1; fi ;;',
    "esac",
    // Write updated state back — use single-quoted printf format with embedded double quotes
    "printf 'type=%s\\nhidden=%s\\nignore=%s\\nexclude=\"%s\"\\n' " +
      '"$type" "$hidden" "$ignore" "$exclude" > "$SF"',
    'if [ "$2" = "header" ]; then',
    '  h=$([ "$hidden" = 1 ] && echo ON || echo OFF)',
    '  i=$([ "$ignore" = 1 ] && echo ON || echo OFF)',
    '  printf \'ctrl-g: toggle gitignored | ctrl-h: toggle dotfiles | hidden:%s | gitignored:%s\' "$h" "$i"',
    "  exit 0",
    "fi",
    'set -- --type "$type"',
    '[ "$hidden" = 1 ] && set -- "$@" --hidden',
    '[ "$ignore" = 1 ] && set -- "$@" --no-ignore',
    'for e in $exclude; do set -- "$@" --exclude "$e"; done',
    'exec fd "$@"',
    "",
  ];
  writeFileSync(helperPath, helperLines.join("\n"), "utf-8");
  chmodSync(helperPath, 0o755);

  // Build fzf command line
  const fzfParts: string[] = [
    "fzf",
    "--height",
    "100%",
    "--prompt",
    shellQuote("> "),
  ];

  if (args.type === "f") {
    fzfParts.push(
      "--preview",
      shellQuote("bat --color=always --style=numbers --line-range=:500 {}"),
    );
  } else {
    fzfParts.push("--preview", shellQuote("ls -la {}"));
  }
  fzfParts.push("--preview-window", shellQuote("right:60%:wrap"));

  fzfParts.push("--bind", shellQuote(`start:reload(${helperPath} none)`));

  if (!args.noToggles) {
    const hStr = hidden ? "ON" : "OFF";
    const iStr = showIgnored ? "ON" : "OFF";
    fzfParts.push(
      "--header",
      shellQuote(
        `ctrl-g: toggle gitignored | ctrl-h: toggle dotfiles | hidden:${hStr} | gitignored:${iStr}`,
      ),
    );
    fzfParts.push(
      "--bind",
      shellQuote(
        `ctrl-g:reload(${helperPath} ignore)+transform-header(${helperPath} ignore header)`,
      ),
    );
    fzfParts.push(
      "--bind",
      shellQuote(
        `ctrl-h:reload(${helperPath} hidden)+transform-header(${helperPath} hidden header)`,
      ),
    );
  }

  // Write runner script — this is what actually runs fzf in the popup
  const runnerLines = [
    "#!/bin/sh",
    `cd ${shellQuote(dir)}`,
    "cleanup() {",
    `  rm -f ${shellQuote(statePath)} ${shellQuote(helperPath)} ${shellQuote(
      runnerPath,
    )}`,
    "}",
    "trap cleanup EXIT INT TERM",
    `selected=$(${fzfParts.join(" ")})`,
    "ec=$?",
    'if [ $ec -eq 0 ] && [ -n "$selected" ]; then',
    ...(args.prefix
      ? [
          `  result=$(echo "$selected" | while IFS= read -r line; do printf '%s ' ${shellQuote(
            args.prefix,
          )}"$line"; done)`,
        ]
      : ["  result=$(echo \"$selected\" | tr '\\n' ' ')"]),
    `  tmux send-keys -t ${shellQuote(args.paneId)} -l "$result"`,
    "fi",
    "exit $ec",
    "",
  ];
  writeFileSync(runnerPath, runnerLines.join("\n"), "utf-8");
  chmodSync(runnerPath, 0o755);

  // Print the runner path — tmux binding will exec it
  process.stdout.write(runnerPath);
}

async function main(): Promise<void> {
  await yargs(hideBin(process.argv))
    .scriptName("tmux-fzf-picker")
    .usage("$0 <command> [options]")
    .command(
      "pick",
      "Generate fzf picker scripts and print the runner path",
      (y) =>
        y
          .option("type", {
            alias: "t",
            choices: ["f", "d"] as const,
            description: "Search type: f=files, d=directories",
            default: "f" as const,
          })
          .option("dir", {
            alias: "d",
            type: "string",
            description: "Directory to search in",
            demandOption: true,
          })
          .option("pane-id", {
            alias: "p",
            type: "string",
            description: "Tmux pane ID to send results to",
            demandOption: true,
          })
          .option("ignore", {
            type: "boolean",
            description:
              "Respect .gitignore (use --no-ignore to show gitignored files)",
            default: true,
          })
          .option("exclude", {
            type: "string",
            array: true,
            description:
              "Exclude patterns (replaces default .git/node_modules)",
            default: [] as string[],
          })
          .option("toggles", {
            type: "boolean",
            description:
              "Enable ctrl-g/ctrl-h toggle bindings (use --no-toggles to disable)",
            default: true,
          })
          .option("prefix", {
            type: "string",
            description: "Prefix to prepend to selected paths",
            default: "",
          }),
      (argv) => {
        handlePick({
          type: argv.type,
          dir: argv.dir,
          paneId: argv.paneId,
          showIgnored: !argv.ignore,
          exclude: argv.exclude,
          noToggles: !argv.toggles,
          prefix: argv.prefix,
        });
      },
    )
    .demandCommand(1, "You must specify a command: pick")
    .strict()
    .help()
    .alias("help", "h").argv;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
