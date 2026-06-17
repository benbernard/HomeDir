import { spawnSync } from "child_process";
import { chmodSync, writeFileSync } from "fs";
import { homedir, tmpdir } from "os";
import { join } from "path";

export type PickerType = "f" | "d";

export interface PickerOptions {
  id: string;
  type: PickerType;
  dir: string;
  showIgnored: boolean;
  exclude: string[];
  noToggles: boolean;
  prefix: string;
  maxDepth: number | undefined;
  listCommand: string | undefined;
  helpTitle: string;
  helpBindingLines: string[];
}

export interface PickerSession {
  dir: string;
  statePath: string;
  helperPath: string;
  fzfCommand: string;
  cleanupPaths: string[];
}

/** Expand $HOME and ~ at the start of a path. */
export function expandHome(p: string): string {
  const home = homedir();
  if (p === "~" || p.startsWith("~/")) {
    return home + p.slice(1);
  }
  return p.replace(/^(\$HOME\b|\$\{HOME\})/, home);
}

/** Shorten an absolute path for display by replacing the home dir with ~. */
export function shortenPath(p: string): string {
  const home = homedir();
  if (p === home) return "~";
  if (p.startsWith(`${home}/`)) return `~${p.slice(home.length)}`;
  return p;
}

export function shellQuote(s: string): string {
  return `'${s.replace(/'/g, "'\\''")}'`;
}

export function tempPath(id: string, ext: string): string {
  const safe = id.replace(/[^a-zA-Z0-9_-]/g, "_");
  return join(tmpdir(), `fzf-picker-${safe}.${ext}`);
}

export function createPickerSession(options: PickerOptions): PickerSession {
  const dir = expandHome(options.dir);
  const dirLabel = shortenPath(dir);
  const statePath = tempPath(options.id, "state");
  const helperPath = tempPath(options.id, "sh");
  const excludes =
    options.exclude.length > 0 ? options.exclude : [".git", "node_modules"];
  const hidden = true;

  const stateLines = [
    `type=${options.type}`,
    `hidden=${hidden ? 1 : 0}`,
    `ignore=${options.showIgnored ? 1 : 0}`,
    `exclude="${excludes.join(" ")}"`,
    `dir="${dir}"`,
    `maxdepth=${options.maxDepth ?? 0}`,
    `listcmd="${options.listCommand ?? ""}"`,
    "help=0",
  ];
  writeFileSync(statePath, `${stateLines.join("\n")}\n`, "utf-8");

  const helpTextLines = [
    "",
    `  ${options.helpTitle}`,
    "  ----------------------------",
    ...options.helpBindingLines,
    "",
    "  Picker Shortcuts",
    "  ----------------------------",
    "  Enter          Select item(s)",
    "  Escape         Cancel",
    "  ctrl-t         Toggle files / dirs",
    "  ctrl-i         Inspect (drill into)",
    "  ctrl-o         Go up (parent dir)",
    "  ctrl-j         Jump to path in query",
    ...(options.noToggles
      ? []
      : [
          "  ctrl-g         Toggle gitignored",
          "  ctrl-h         Toggle dotfiles",
        ]),
    "  ctrl-/         Toggle this help",
    "",
  ];

  const helperScriptLines = [
    "#!/bin/sh",
    `SF=${shellQuote(statePath)}`,
    `HELPER=${shellQuote(helperPath)}`,
    `ORIGDIR=${shellQuote(dir)}`,
    `HOME_PREFIX=${shellQuote(homedir())}`,
    '. "$SF"',
    "",
    "shorten() {",
    '  case "$1" in',
    '    "$HOME_PREFIX") echo "~" ;;',
    '    "$HOME_PREFIX"/*) echo "~${1#$HOME_PREFIX}" ;;',
    '    *) echo "$1" ;;',
    "  esac",
    "}",
    "",
    'if [ "$1" = "help-text" ]; then',
    `  printf ${shellQuote(`${helpTextLines.join("\\n")}\\n`)}`,
    "  exit 0",
    "fi",
    "",
    'if [ "$1" = "preview" ]; then',
    '  cd "$dir" || exit 1',
    '  if [ -d "$2" ]; then',
    '    ls -la "$2"',
    '  elif file --brief --mime "$2" 2>/dev/null | grep -qv "^text/\\|^application/json\\|^application/xml\\|^application/csv\\|^inode/"; then',
    '    file --brief "$2"',
    '    echo ""',
    '    ls -lh "$2" | tail -1',
    "  else",
    '    bat --color=always --style=numbers --line-range=:500 "$2"',
    "  fi",
    "  exit 0",
    "fi",
    "",
    'if [ "$1" = "run" ]; then',
    '  cd "$dir" || exit 1',
    '  if [ -n "$listcmd" ]; then',
    '    exec sh -c "$listcmd"',
    "  fi",
    '  set -- --type "$type"',
    '  [ "$hidden" = 1 ] && set -- "$@" --hidden',
    '  [ "$ignore" = 1 ] && set -- "$@" --no-ignore',
    '  [ "$maxdepth" -gt 0 ] 2>/dev/null && set -- "$@" --max-depth "$maxdepth"',
    '  for e in $exclude; do set -- "$@" --exclude "$e"; done',
    '  exec fd "$@"',
    "fi",
    "",
    "save_state() {",
    '  printf \'type=%s\\nhidden=%s\\nignore=%s\\nexclude="%s"\\ndir="%s"\\nmaxdepth=%s\\nlistcmd="%s"\\nhelp=%s\\n\' ' +
      '"$type" "$hidden" "$ignore" "$exclude" "$dir" "$maxdepth" "$listcmd" "$help" > "$SF"',
    "}",
    "",
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
    "    maxdepth=0",
    "    ;;",
    "  up)",
    '    dir=$(cd "$dir/.." && pwd)',
    "    maxdepth=0",
    "    ;;",
    "  goto)",
    '    target="$3"',
    '    case "$target" in',
    '      "~/"*) target="$HOME_PREFIX${target#"~"}" ;;',
    '      "~") target="$HOME_PREFIX" ;;',
    "    esac",
    '    if [ -d "$target" ]; then',
    '      dir=$(cd "$target" && pwd)',
    "    fi",
    "    maxdepth=0",
    "    ;;",
    "esac",
    "",
    "was_help=$help",
    "help=0",
    "save_state",
    "",
    'label=$(shorten "$dir")',
    't=$([ "$type" = "f" ] && echo "files" || echo "dirs")',
    'h=$([ "$hidden" = 1 ] && echo ON || echo OFF)',
    'i=$([ "$ignore" = 1 ] && echo ON || echo OFF)',
    'header=$(printf \'%s | %s | dotfiles:%s ignored:%s\' "$label" "$t" "$h" "$i")',
    "",
    'out=$(printf \'reload(%s run)+change-border-label( %s )\' "$HELPER" "$header")',
    'if [ "$was_help" = 1 ]; then',
    `  out=$(printf '%s+change-preview(${helperPath} preview {})' "$out")`,
    "fi",
    'if [ "$2" = "goto" ] || [ "$2" = "cd" ] || [ "$2" = "up" ]; then',
    '  out="$out+clear-query"',
    "fi",
    "printf '%s' \"$out\"",
    "",
  ];
  writeFileSync(helperPath, helperScriptLines.join("\n"), "utf-8");
  chmodSync(helperPath, 0o755);

  const fzfParts: string[] = [
    "fzf",
    "--height",
    "100%",
    "--prompt",
    shellQuote("> "),
    "--preview",
    shellQuote(`${helperPath} preview {}`),
    "--preview-window",
    shellQuote("right:60%:wrap"),
    "--border-label",
    shellQuote(
      ` ${dirLabel} | ${
        options.type === "f" ? "files" : "dirs"
      } | dotfiles:ON ignored:${options.showIgnored ? "ON" : "OFF"} `,
    ),
    "--bind",
    shellQuote(`ctrl-t:transform(${helperPath} actions type)`),
    "--bind",
    shellQuote(`ctrl-i:transform(${helperPath} actions cd {})`),
    "--bind",
    shellQuote(`ctrl-o:transform(${helperPath} actions up)`),
    "--bind",
    shellQuote(`ctrl-j:transform(${helperPath} actions goto {q})`),
    "--bind",
    shellQuote(`ctrl-/:transform(${helperPath} actions help)`),
  ];

  if (!options.noToggles) {
    fzfParts.push(
      "--bind",
      shellQuote(`ctrl-g:transform(${helperPath} actions ignore)`),
      "--bind",
      shellQuote(`ctrl-h:transform(${helperPath} actions hidden)`),
    );
  }

  return {
    dir,
    statePath,
    helperPath,
    fzfCommand: fzfParts.join(" "),
    cleanupPaths: [statePath, helperPath],
  };
}

export function resultShellLines(options: {
  selectedVar: string;
  resultVar: string;
  statePath: string;
  prefix: string;
}): string[] {
  const { selectedVar, resultVar } = options;

  return [
    `. ${shellQuote(options.statePath)}`,
    `HOME_PREFIX=${shellQuote(homedir())}`,
    'if [ "$dir" = "$ORIGDIR" ]; then',
    ...(options.prefix
      ? [
          `  ${resultVar}=$(echo "$${selectedVar}" | while IFS= read -r line; do printf '%s ' ${shellQuote(
            options.prefix,
          )}"$line"; done)`,
        ]
      : [`  ${resultVar}=$(echo "$${selectedVar}" | tr '\\n' ' ')`]),
    "else",
    `  ${resultVar}=$(echo "$${selectedVar}" | while IFS= read -r line; do`,
    '    full="$dir/$line"',
    '    case "$full" in',
    '      ("$HOME_PREFIX"/*) printf \'~%s \' "${full#$HOME_PREFIX}" ;;',
    "      (*) printf '%s ' \"$full\" ;;",
    "    esac",
    "  done)",
    "fi",
  ];
}

export function runPicker(options: PickerOptions): string {
  const session = createPickerSession(options);
  const script = [
    "#!/bin/sh",
    `cd ${shellQuote(session.dir)}`,
    `ORIGDIR=${shellQuote(session.dir)}`,
    `selected=$(${session.helperPath} run | ${session.fzfCommand})`,
    "ec=$?",
    'if [ $ec -eq 0 ] && [ -n "$selected" ]; then',
    ...resultShellLines({
      selectedVar: "selected",
      resultVar: "result",
      statePath: session.statePath,
      prefix: options.prefix,
    }).map((line) => `  ${line}`),
    '  printf "%s" "$result"',
    "fi",
  ].join("\n");

  try {
    const result = spawnSync("sh", ["-c", script], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "inherit"],
    });
    if (result.error) {
      throw result.error;
    }
    return result.stdout ?? "";
  } finally {
    cleanupPickerSession(session);
  }
}

export function cleanupPickerSession(session: PickerSession): void {
  for (const path of session.cleanupPaths) {
    try {
      spawnSync("rm", ["-f", path], { stdio: "ignore" });
    } catch {
      // Best-effort cleanup only.
    }
  }
}
