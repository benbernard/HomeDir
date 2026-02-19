#!/usr/bin/env tsx

import { spawnSync } from "child_process";
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
  return p.replace(/^(\$HOME\b|\$\{HOME\})/, home);
}

/** Shorten an absolute path for display (replace home dir with ~) */
function shortenPath(p: string): string {
  const home = homedir();
  if (p === home) return "~";
  if (p.startsWith(`${home}/`)) return `~${p.slice(home.length)}`;
  return p;
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
  const dirLabel = shortenPath(dir);
  const statePath = tempPath(args.paneId, "state");
  const helperPath = tempPath(args.paneId, "sh");
  const runnerPath = tempPath(args.paneId, "run");

  const excludes =
    args.exclude.length > 0 ? args.exclude : [".git", "node_modules"];
  const hidden = true;
  const showIgnored = args.showIgnored;

  // State file uses absolute dir — tracks current working directory
  const stateLines = [
    `type=${args.type}`,
    `hidden=${hidden ? 1 : 0}`,
    `ignore=${showIgnored ? 1 : 0}`,
    `exclude="${excludes.join(" ")}"`,
    `dir="${dir}"`,
    "help=0",
  ];
  writeFileSync(statePath, `${stateLines.join("\n")}\n`, "utf-8");

  // Help text
  const helpTextLines = [
    "",
    "  Tmux Bindings",
    "  ────────────────────────────",
    "  alt-p / alt-P  Pick in cwd (files / dirs)",
    "  alt-h / alt-H  Pick in $HOME (files / dirs)",
    "  alt-r / alt-R  Pick in ~/repos (dirs / files)",
    "",
    "  Picker Shortcuts",
    "  ────────────────────────────",
    "  Enter          Select item(s)",
    "  Escape         Cancel",
    "  ctrl-t         Toggle files / dirs",
    "  ctrl-i         Inspect (drill into)",
    "  ctrl-o         Go up (parent dir)",
    "  ctrl-j         Jump to path in query",
    ...(args.noToggles
      ? []
      : [
          "  ctrl-g         Toggle gitignored",
          "  ctrl-h         Toggle dotfiles",
        ]),
    "  ctrl-/         Toggle this help",
    "",
  ];

  // Helper script — four modes:
  //   helper run                      — cd to $dir, run fd (for reload)
  //   helper preview <item>           — cd to $dir, preview item (for --preview)
  //   helper help-text                — print help (for change-preview)
  //   helper actions <action> [arg]   — mutate state, output fzf actions (for transform)
  const helperScriptLines = [
    "#!/bin/sh",
    `SF=${shellQuote(statePath)}`,
    `HELPER=${shellQuote(helperPath)}`,
    `ORIGDIR=${shellQuote(dir)}`,
    `HOME_PREFIX=${shellQuote(homedir())}`,
    '. "$SF"',
    "",
    "# Shorten absolute path for display",
    "shorten() {",
    '  case "$1" in',
    '    "$HOME_PREFIX") echo "~" ;;',
    '    "$HOME_PREFIX"/*) echo "~${1#$HOME_PREFIX}" ;;',
    '    *) echo "$1" ;;',
    "  esac",
    "}",
    "",
    '# "help-text" mode',
    'if [ "$1" = "help-text" ]; then',
    `  printf ${shellQuote(`${helpTextLines.join("\\n")}\\n`)}`,
    "  exit 0",
    "fi",
    "",
    '# "preview" mode: cd to current dir and preview the item',
    'if [ "$1" = "preview" ]; then',
    '  cd "$dir" || exit 1',
    '  if [ -d "$2" ]; then',
    '    ls -la "$2"',
    "  else",
    '    bat --color=always --style=numbers --line-range=:500 "$2"',
    "  fi",
    "  exit 0",
    "fi",
    "",
    '# "run" mode: cd to current dir and run fd',
    'if [ "$1" = "run" ]; then',
    '  cd "$dir" || exit 1',
    '  set -- --type "$type"',
    '  [ "$hidden" = 1 ] && set -- "$@" --hidden',
    '  [ "$ignore" = 1 ] && set -- "$@" --no-ignore',
    '  for e in $exclude; do set -- "$@" --exclude "$e"; done',
    '  exec fd "$@"',
    "fi",
    "",
    '# "actions" mode: mutate state, output fzf actions',
    "save_state() {",
    '  printf \'type=%s\\nhidden=%s\\nignore=%s\\nexclude="%s"\\ndir="%s"\\nhelp=%s\\n\' ' +
      '"$type" "$hidden" "$ignore" "$exclude" "$dir" "$help" > "$SF"',
    "}",
    "",
    "# Help toggle: swap preview, no reload needed",
    'if [ "$2" = "help" ]; then',
    '  if [ "$help" = 1 ]; then',
    "    help=0; save_state",
    `    printf 'change-preview(${helperPath} preview {})'`,
    "  else",
    "    help=1; save_state",
    `    printf 'change-preview(${helperPath} help-text)'`,
    "  fi",
    "  exit 0",
    "fi",
    "",
    "# All other actions",
    'case "$2" in',
    '  hidden) if [ "$hidden" = 1 ]; then hidden=0; else hidden=1; fi ;;',
    '  ignore) if [ "$ignore" = 1 ]; then ignore=0; else ignore=1; fi ;;',
    '  type) if [ "$type" = "f" ]; then type=d; else type=f; fi ;;',
    "  cd)",
    '    target="$3"',
    '    if [ -n "$target" ] && [ -d "$dir/$target" ]; then',
    '      dir=$(cd "$dir/$target" && pwd)',
    '    elif [ -n "$target" ] && [ -f "$dir/$target" ]; then',
    '      dir=$(cd "$dir/$(dirname "$target")" && pwd)',
    "    fi",
    "    ;;",
    "  up)",
    '    dir=$(cd "$dir/.." && pwd)',
    "    ;;",
    "  goto)",
    '    target="$3"',
    "    # Expand ~ at start",
    '    case "$target" in',
    '      "~/"*) target="$HOME_PREFIX${target#"~"}" ;;',
    '      "~") target="$HOME_PREFIX" ;;',
    "    esac",
    '    if [ -d "$target" ]; then',
    '      dir=$(cd "$target" && pwd)',
    "    fi",
    "    ;;",
    "esac",
    "",
    "# Auto-dismiss help on any non-help action",
    "was_help=$help",
    "help=0",
    "save_state",
    "",
    "# Compute border label",
    'label=$(shorten "$dir")',
    't=$([ "$type" = "f" ] && echo "files" || echo "dirs")',
    'h=$([ "$hidden" = 1 ] && echo ON || echo OFF)',
    'i=$([ "$ignore" = 1 ] && echo ON || echo OFF)',
    'header=$(printf \'%s | %s | dotfiles:%s ignored:%s\' "$label" "$t" "$h" "$i")',
    "",
    "# Output fzf actions",
    'out=$(printf \'reload(%s run)+change-border-label( %s )\' "$HELPER" "$header")',
    'if [ "$was_help" = 1 ]; then',
    `  out=$(printf '%s+change-preview(${helperPath} preview {})' "$out")`,
    "fi",
    "# Clear query after goto",
    'if [ "$2" = "goto" ]; then',
    '  out="$out+clear-query"',
    "fi",
    "printf '%s' \"$out\"",
    "",
  ];
  writeFileSync(helperPath, helperScriptLines.join("\n"), "utf-8");
  chmodSync(helperPath, 0o755);

  // Build fzf command line
  const fzfParts: string[] = [
    "fzf",
    "--height",
    "100%",
    "--prompt",
    shellQuote("> "),
  ];

  // Preview via helper (so it cd's to the right dir)
  fzfParts.push("--preview", shellQuote(`${helperPath} preview {}`));
  fzfParts.push("--preview-window", shellQuote("right:60%:wrap"));

  // Initial border label
  const typeStr = args.type === "f" ? "files" : "dirs";
  const hStr = hidden ? "ON" : "OFF";
  const iStr = showIgnored ? "ON" : "OFF";
  fzfParts.push(
    "--border-label",
    shellQuote(` ${dirLabel} | ${typeStr} | dotfiles:${hStr} ignored:${iStr} `),
  );

  // Initial load
  fzfParts.push(
    "--bind",
    shellQuote(`start:transform(${helperPath} actions none)`),
  );

  // Always-available bindings
  fzfParts.push(
    "--bind",
    shellQuote(`ctrl-t:transform(${helperPath} actions type)`),
  );
  fzfParts.push(
    "--bind",
    shellQuote(`ctrl-i:transform(${helperPath} actions cd {})`),
  );
  fzfParts.push(
    "--bind",
    shellQuote(`ctrl-o:transform(${helperPath} actions up)`),
  );
  fzfParts.push(
    "--bind",
    shellQuote(`ctrl-j:transform(${helperPath} actions goto {q})`),
  );
  fzfParts.push(
    "--bind",
    shellQuote(`ctrl-/:transform(${helperPath} actions help)`),
  );

  // Conditional toggle bindings
  if (!args.noToggles) {
    fzfParts.push(
      "--bind",
      shellQuote(`ctrl-g:transform(${helperPath} actions ignore)`),
    );
    fzfParts.push(
      "--bind",
      shellQuote(`ctrl-h:transform(${helperPath} actions hidden)`),
    );
  }

  // Runner script — runs fzf in the popup, sends selection to pane
  const runnerLines = [
    "#!/bin/sh",
    `cd ${shellQuote(dir)}`,
    `ORIGDIR=${shellQuote(dir)}`,
    `SF=${shellQuote(statePath)}`,
    `HOME_PREFIX=${shellQuote(homedir())}`,
    "cleanup() {",
    `  rm -f ${shellQuote(statePath)} ${shellQuote(helperPath)} ${shellQuote(
      runnerPath,
    )}`,
    "}",
    "trap cleanup EXIT INT TERM",
    `selected=$(${fzfParts.join(" ")})`,
    "ec=$?",
    'if [ $ec -eq 0 ] && [ -n "$selected" ]; then',
    '  . "$SF"',
    '  if [ "$dir" = "$ORIGDIR" ]; then',
    // In original dir: use paths as-is (or with prefix)
    ...(args.prefix
      ? [
          `    result=$(echo "$selected" | while IFS= read -r line; do printf '%s ' ${shellQuote(
            args.prefix,
          )}"$line"; done)`,
        ]
      : ["    result=$(echo \"$selected\" | tr '\\n' ' ')"]),
    "  else",
    // After goto/inspect: construct tilde-shortened absolute paths
    '    result=$(echo "$selected" | while IFS= read -r line; do',
    '      full="$dir/$line"',
    '      case "$full" in',
    '        ("$HOME_PREFIX"/*) printf \'~%s \' "${full#$HOME_PREFIX}" ;;',
    "        (*) printf '%s ' \"$full\" ;;",
    "      esac",
    "    done)",
    "  fi",
    `  tmux send-keys -t ${shellQuote(args.paneId)} -l "$result"`,
    "fi",
    "exit 0",
    "",
  ];
  writeFileSync(runnerPath, runnerLines.join("\n"), "utf-8");
  chmodSync(runnerPath, 0o755);

  // Open the popup
  spawnSync("tmux", [
    "display-popup",
    "-E",
    "-w",
    "80%",
    "-h",
    "80%",
    `exec ${runnerPath}`,
  ]);
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
