#!/usr/bin/env tsx

/**
 * Launch terminal-hosted FZF pickers for GUI hotkeys.
 *
 * Example Alfred command:
 *   gui-fzf-picker paste --preset context-files
 *
 * The paste command prints only the selected text to stdout, so Alfred can
 * paste that output into the originally focused app.
 */

import { spawnSync } from "child_process";
import {
  chmodSync,
  existsSync,
  readFileSync,
  readdirSync,
  rmSync,
  writeFileSync,
} from "fs";
import { homedir } from "os";
import { basename, join } from "path";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import {
  type PickerOptions,
  type PickerType,
  runPicker,
  shellQuote,
  shortenPath,
  tempPath,
} from "./lib/fzf-picker";

const presets = [
  "context-files",
  "context-dirs",
  "home-files",
  "home-dirs",
  "repos-dirs",
  "repos-files",
  "downloads-files",
] as const;

type Preset = (typeof presets)[number];

interface ContextRoot {
  label: string;
  displayPath: string;
  dir: string;
}

function presetToPickerOptions(
  preset: Preset,
  id: string,
): PickerOptions | null {
  const home = homedir();
  const repos = join(home, "repos");

  switch (preset) {
    case "home-files":
      return baseOptions({
        id,
        type: "f",
        dir: home,
        exclude: ["repos"],
        helpBindingLines: [
          "  alt-h          Pick files in $HOME",
          "  alt-H          Pick dirs in $HOME",
        ],
      });
    case "home-dirs":
      return baseOptions({
        id,
        type: "d",
        dir: home,
        exclude: ["repos"],
        helpBindingLines: [
          "  alt-h          Pick files in $HOME",
          "  alt-H          Pick dirs in $HOME",
        ],
      });
    case "repos-dirs":
      return baseOptions({
        id,
        type: "d",
        dir: repos,
        noToggles: true,
        prefix: "~/repos/",
        maxDepth: 1,
        helpBindingLines: [
          "  alt-r          Pick repo dirs in ~/repos",
          "  alt-R          Pick files in ~/repos",
        ],
      });
    case "repos-files":
      return baseOptions({
        id,
        type: "f",
        dir: repos,
        noToggles: true,
        prefix: "~/repos/",
        helpBindingLines: [
          "  alt-r          Pick repo dirs in ~/repos",
          "  alt-R          Pick files in ~/repos",
        ],
      });
    case "downloads-files":
      return baseOptions({
        id,
        type: "f",
        dir: join(home, "Downloads"),
        noToggles: true,
        prefix: "~/Downloads/",
        listCommand: "ls -1t",
        helpBindingLines: ["  alt-d          Pick newest files in ~/Downloads"],
      });
    case "context-files":
    case "context-dirs":
      return null;
  }
}

function baseOptions(args: {
  id: string;
  type: PickerType;
  dir: string;
  exclude?: string[];
  noToggles?: boolean;
  prefix?: string;
  maxDepth?: number;
  listCommand?: string;
  helpBindingLines: string[];
}): PickerOptions {
  return {
    id: args.id,
    type: args.type,
    dir: args.dir,
    showIgnored: true,
    exclude: args.exclude ?? [],
    noToggles: args.noToggles ?? false,
    prefix: args.prefix ?? "",
    maxDepth: args.maxDepth,
    listCommand: args.listCommand,
    helpTitle: "GUI Picker Bindings",
    helpBindingLines: args.helpBindingLines,
  };
}

function contextPickerOptions(
  preset: Preset,
  id: string,
): PickerOptions | null {
  const root = chooseContextRoot();
  if (!root) return null;

  const home = homedir();
  const repos = join(home, "repos");
  const type = preset === "context-dirs" ? "d" : "f";
  const prefix =
    root.dir === home
      ? "~/"
      : root.dir.startsWith(`${repos}/`)
        ? `~/repos/${basename(root.dir)}/`
        : `${shortenPath(root.dir)}/`;

  return baseOptions({
    id,
    type,
    dir: root.dir,
    prefix,
    helpBindingLines: [
      "  alt-p          Pick root, then files",
      "  alt-P          Pick root, then dirs",
    ],
  });
}

function chooseContextRoot(): ContextRoot | null {
  const roots = contextRoots();
  const input = `${roots
    .map((root) => `${root.label}\t${root.displayPath}\t${root.dir}`)
    .join("\n")}\n`;

  const result = spawnSync(
    "fzf",
    [
      "--height",
      "100%",
      "--reverse",
      "--border",
      "--prompt",
      "root> ",
      "--delimiter",
      "\t",
      "--with-nth",
      "1,2",
      "--preview",
      "ls -la {3}",
      "--preview-window",
      "right:60%:wrap",
      "+m",
    ],
    {
      input,
      encoding: "utf8",
      stdio: ["pipe", "pipe", "inherit"],
    },
  );

  if (result.status !== 0 || !result.stdout) {
    return null;
  }

  const selectedDir = result.stdout.trimEnd().split("\t")[2];
  return roots.find((root) => root.dir === selectedDir) ?? null;
}

function contextRoots(): ContextRoot[] {
  const home = homedir();
  const repos = join(home, "repos");
  const roots: ContextRoot[] = [
    {
      label: "home",
      displayPath: "~",
      dir: home,
    },
  ];

  if (!existsSync(repos)) {
    return roots;
  }

  const repoRoots = readdirSync(repos, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      const dir = join(repos, entry.name);
      return {
        label: entry.name,
        displayPath: shortenPath(dir),
        dir,
      };
    })
    .sort((left, right) => left.label.localeCompare(right.label));

  return [...roots, ...repoRoots];
}

function runPreset(preset: Preset): string {
  const id = `gui-${preset}-${process.pid}-${Date.now()}`;
  const options =
    preset === "context-files" || preset === "context-dirs"
      ? contextPickerOptions(preset, id)
      : presetToPickerOptions(preset, id);

  if (!options) return "";
  return runPicker(options);
}

function terminalRunnerPath(preset: Preset): string {
  return tempPath(`gui-${preset}-${process.pid}-${Date.now()}`, "run");
}

function writeTerminalRunner(args: {
  preset: Preset;
  resultFile: string;
  doneFile: string;
  pidFile: string;
}): string {
  const runnerPath = terminalRunnerPath(args.preset);
  const lines = [
    "#!/bin/sh",
    `echo $$ > ${shellQuote(args.pidFile)}`,
    'export PATH="$HOME/bin/ts/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"',
    ...envExportLines(["FZF_DEFAULT_OPTS"]),
    "cleanup() {",
    `  touch ${shellQuote(args.doneFile)}`,
    "}",
    "trap cleanup EXIT INT TERM",
    "gui-fzf-picker run-terminal \\",
    `  --preset ${shellQuote(args.preset)} \\`,
    `  --result-file ${shellQuote(args.resultFile)} \\`,
    `  --done-file ${shellQuote(args.doneFile)}`,
  ];
  writeFileSync(runnerPath, `${lines.join("\n")}\n`, "utf-8");
  chmodSync(runnerPath, 0o755);
  return runnerPath;
}

function envExportLines(names: string[]): string[] {
  return names.flatMap((name) => {
    const value = process.env[name];
    return value === undefined ? [] : [`export ${name}=${shellQuote(value)}`];
  });
}

function runTerminalApp(args: {
  runnerPath: string;
  doneFile: string;
  timeoutSeconds: number;
}): void {
  const script = `
set donePath to system attribute "GUI_FZF_DONE"
set runnerPath to system attribute "GUI_FZF_RUNNER"
set timeoutSeconds to (system attribute "GUI_FZF_TIMEOUT") as integer
tell application "Terminal"
  activate
  set pickerWindow to do script quoted form of runnerPath
end tell
set sawDone to false
repeat (timeoutSeconds * 10) times
  delay 0.1
  try
    do shell script "test -f " & quoted form of donePath
    set sawDone to true
    exit repeat
  end try
end repeat
tell application "Terminal"
  try
    close pickerWindow saving no
  end try
end tell
if sawDone is false then error "timed out waiting for gui-fzf-picker"
`;

  const result = spawnSync("osascript", [], {
    input: script,
    encoding: "utf8",
    env: {
      ...process.env,
      GUI_FZF_DONE: args.doneFile,
      GUI_FZF_RUNNER: args.runnerPath,
      GUI_FZF_TIMEOUT: String(args.timeoutSeconds),
    },
    stdio: ["pipe", "pipe", "pipe"],
  });

  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout || "Terminal launch failed");
  }
}

function handlePaste(args: { preset: Preset; timeoutSeconds: number }): void {
  const id = `gui-${args.preset}-${process.pid}-${Date.now()}`;
  const resultFile = tempPath(id, "result");
  const doneFile = tempPath(id, "done");
  const pidFile = tempPath(id, "pid");
  const runnerPath = writeTerminalRunner({
    preset: args.preset,
    resultFile,
    doneFile,
    pidFile,
  });

  try {
    runTerminalApp({
      runnerPath,
      doneFile,
      timeoutSeconds: args.timeoutSeconds,
    });
    if (existsSync(resultFile)) {
      process.stdout.write(readFileSync(resultFile, "utf8"));
    }
  } catch (err) {
    killRunnerFromPidFile(pidFile);
    throw err;
  } finally {
    for (const path of [resultFile, doneFile, pidFile, runnerPath]) {
      rmSync(path, { force: true });
    }
  }
}

function killRunnerFromPidFile(pidFile: string): void {
  if (!existsSync(pidFile)) return;

  const pid = Number.parseInt(readFileSync(pidFile, "utf8").trim(), 10);
  if (!Number.isFinite(pid)) return;

  const pids = descendantPids(pid);
  for (const targetPid of [...pids.reverse(), pid]) {
    spawnSync("kill", ["-TERM", String(targetPid)], { stdio: "ignore" });
  }
}

function descendantPids(pid: number): number[] {
  const result = spawnSync("pgrep", ["-P", String(pid)], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  });
  const children = (result.stdout ?? "")
    .split("\n")
    .map((line) => Number.parseInt(line.trim(), 10))
    .filter((childPid) => Number.isFinite(childPid));

  return children.flatMap((childPid) => [
    childPid,
    ...descendantPids(childPid),
  ]);
}

function handleRunTerminal(args: {
  preset: Preset;
  resultFile: string;
  doneFile: string;
}): void {
  try {
    const result = runPreset(args.preset);
    if (result) {
      writeFileSync(args.resultFile, result, "utf8");
    }
  } finally {
    writeFileSync(args.doneFile, "", "utf8");
  }
}

async function main(): Promise<void> {
  await yargs(hideBin(process.argv))
    .scriptName("gui-fzf-picker")
    .usage("$0 <command> [options]")
    .command(
      "paste",
      "Run a terminal-hosted FZF picker and print the selected paste text",
      (y) =>
        y
          .option("preset", {
            choices: presets,
            description: "Picker preset to run",
            demandOption: true,
          })
          .option("timeout-seconds", {
            type: "number",
            description: "Maximum time to wait for the terminal picker",
            default: 600,
          })
          .example(
            "$0 paste --preset context-files",
            "Pick a root, then pick files for Alfred to paste",
          )
          .example(
            "$0 paste --preset repos-dirs",
            "Pick a direct repo under ~/repos for Alfred to paste",
          ),
      (argv) => {
        handlePaste({
          preset: argv.preset,
          timeoutSeconds: argv.timeoutSeconds,
        });
      },
    )
    .command(
      "run-terminal",
      "Internal command run inside the terminal window",
      (y) =>
        y
          .option("preset", {
            choices: presets,
            description: "Picker preset to run",
            demandOption: true,
          })
          .option("result-file", {
            type: "string",
            description: "Path where selected paste text should be written",
            demandOption: true,
          })
          .option("done-file", {
            type: "string",
            description: "Path touched when the terminal picker is done",
            demandOption: true,
          }),
      (argv) => {
        handleRunTerminal({
          preset: argv.preset,
          resultFile: argv.resultFile,
          doneFile: argv.doneFile,
        });
      },
    )
    .demandCommand(1, "You must specify a command")
    .strict()
    .help()
    .alias("help", "h").argv;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
