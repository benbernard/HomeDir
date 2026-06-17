#!/usr/bin/env tsx

import { spawnSync } from "child_process";
import { chmodSync, writeFileSync } from "fs";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import {
  type PickerType,
  cleanupPickerSession,
  createPickerSession,
  resultShellLines,
  shellQuote,
  tempPath,
} from "./lib/fzf-picker";

function handlePick(args: {
  type: PickerType;
  dir: string;
  paneId: string;
  showIgnored: boolean;
  exclude: string[];
  noToggles: boolean;
  prefix: string;
  maxDepth: number | undefined;
  listCommand: string | undefined;
}): void {
  const session = createPickerSession({
    id: args.paneId,
    type: args.type,
    dir: args.dir,
    showIgnored: args.showIgnored,
    exclude: args.exclude,
    noToggles: args.noToggles,
    prefix: args.prefix,
    maxDepth: args.maxDepth,
    listCommand: args.listCommand,
    helpTitle: "Tmux Bindings",
    helpBindingLines: [
      "  alt-p / alt-P  Pick in cwd (files / dirs)",
      "  alt-h / alt-H  Pick in $HOME (files / dirs)",
      "  alt-r / alt-R  Pick in ~/repos (dirs / files)",
      "  alt-d          Pick in ~/Downloads (newest first)",
    ],
  });
  const runnerPath = tempPath(args.paneId, "run");

  const runnerLines = [
    "#!/bin/sh",
    `cd ${shellQuote(session.dir)}`,
    `ORIGDIR=${shellQuote(session.dir)}`,
    "cleanup() {",
    `  rm -f ${session.cleanupPaths.map(shellQuote).join(" ")} ${shellQuote(
      runnerPath,
    )}`,
    "}",
    "trap cleanup EXIT INT TERM",
    `selected=$(${session.helperPath} run | ${session.fzfCommand})`,
    "ec=$?",
    'if [ $ec -eq 0 ] && [ -n "$selected" ]; then',
    ...resultShellLines({
      selectedVar: "selected",
      resultVar: "result",
      statePath: session.statePath,
      prefix: args.prefix,
    }).map((line) => `  ${line}`),
    `  tmux send-keys -t ${shellQuote(args.paneId)} -l "$result"`,
    "fi",
    "exit 0",
    "",
  ];

  writeFileSync(runnerPath, runnerLines.join("\n"), "utf-8");
  chmodSync(runnerPath, 0o755);

  const result = spawnSync("tmux", [
    "display-popup",
    "-E",
    "-w",
    "80%",
    "-h",
    "80%",
    `exec ${runnerPath}`,
  ]);
  if (result.error || result.status !== 0) {
    cleanupPickerSession(session);
    spawnSync("rm", ["-f", runnerPath], { stdio: "ignore" });
  }
}

async function main(): Promise<void> {
  await yargs(hideBin(process.argv))
    .scriptName("tmux-fzf-picker")
    .usage("$0 <command> [options]")
    .command(
      "pick",
      "Open fzf picker in a tmux popup",
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
          })
          .option("max-depth", {
            type: "number",
            description: "Maximum directory depth for fd (0 = unlimited)",
          })
          .option("list-command", {
            type: "string",
            description:
              "Custom shell command to list files (overrides fd, runs after cd to dir)",
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
          maxDepth: argv.maxDepth,
          listCommand: argv.listCommand,
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
