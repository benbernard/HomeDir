#!/usr/bin/env tsx

/**
 * tmux-health-check: Verify the nested tmux keybinding chain is healthy.
 *
 * Checks:
 * 1. Config files exist and source the right things
 * 2. Outer tmux server state (bindings, options)
 * 3. Nested tmux server state (bindings, options)
 * 4. Key partitioning (outer doesn't steal nested keys, nested has its keys)
 * 5. tmux-swap-or-move-window is on PATH
 * 6. Ghostty config sends correct escape sequences
 */

import { $ } from "zx";

$.verbose = false;

// Colors for output
const RED = "\x1b[31m";
const GREEN = "\x1b[32m";
const YELLOW = "\x1b[33m";
const CYAN = "\x1b[36m";
const BOLD = "\x1b[1m";
const RESET = "\x1b[0m";

const PASS = `${GREEN}✓${RESET}`;
const FAIL = `${RED}✗${RESET}`;
const WARN = `${YELLOW}⚠${RESET}`;
const INFO = `${CYAN}ℹ${RESET}`;

let failures = 0;
let warnings = 0;
let passes = 0;

function pass(msg: string) {
  console.log(`  ${PASS} ${msg}`);
  passes++;
}

function fail(msg: string, detail?: string) {
  console.log(`  ${FAIL} ${msg}`);
  if (detail) console.log(`      ${RED}${detail}${RESET}`);
  failures++;
}

function warn(msg: string, detail?: string) {
  console.log(`  ${WARN} ${msg}`);
  if (detail) console.log(`      ${YELLOW}${detail}${RESET}`);
  warnings++;
}

function info(msg: string) {
  console.log(`  ${INFO} ${msg}`);
}

function section(name: string) {
  console.log(`\n${BOLD}${name}${RESET}`);
}

async function run(cmd: string): Promise<string> {
  try {
    const result = await $`bash -c ${cmd}`;
    return result.stdout.trim();
  } catch {
    return "";
  }
}

async function fileExists(path: string): Promise<boolean> {
  try {
    await $`test -f ${path}`;
    return true;
  } catch {
    return false;
  }
}

async function fileContains(path: string, pattern: string): Promise<boolean> {
  try {
    await $`grep -q ${pattern} ${path}`;
    return true;
  } catch {
    return false;
  }
}

// Always use explicit socket names. Bare `tmux` inherits $TMUX which may
// point to the nested server when this script runs inside a nested pane.
const OUTER_SOCKET = "default";
const NESTED_SOCKET = "nested";

async function tmuxServerRunning(socket: string): Promise<boolean> {
  try {
    await $`tmux -L ${socket} list-sessions`;
    return true;
  } catch {
    return false;
  }
}

async function getTmuxBindings(
  socket: string,
  table: string,
): Promise<string[]> {
  try {
    const cmd = `tmux -L ${socket} list-keys -T ${table}`;
    const result = await run(cmd);
    return result.split("\n").filter((l) => l.length > 0);
  } catch {
    return [];
  }
}

async function getTmuxOption(
  socket: string,
  option: string,
  server = false,
): Promise<string> {
  const flag = server ? "-s" : "-g";
  const cmd = `tmux -L ${socket} show-option ${flag} ${option} 2>/dev/null`;
  return run(cmd);
}

// ──────────────────────────────────────────────────────────────────────────────
// Checks
// ──────────────────────────────────────────────────────────────────────────────

async function checkConfigFiles() {
  section("Config Files");

  const home = process.env.HOME || "/Users/benbernard";

  // Check existence
  for (const file of [".tmux.shared.conf", ".tmux.conf", ".tmux.nested.conf"]) {
    if (await fileExists(`${home}/${file}`)) {
      pass(`${file} exists`);
    } else {
      fail(`${file} missing`);
    }
  }

  // Check sourcing relationships
  if (await fileContains(`${home}/.tmux.conf`, "source-file.*tmux.shared")) {
    pass(".tmux.conf sources .tmux.shared.conf");
  } else {
    fail(".tmux.conf does not source .tmux.shared.conf");
  }

  if (
    await fileContains(`${home}/.tmux.nested.conf`, "source-file.*tmux.shared")
  ) {
    pass(".tmux.nested.conf sources .tmux.shared.conf");
  } else {
    fail(".tmux.nested.conf does not source .tmux.shared.conf");
  }

  // Nested should NOT source the full outer config (that was the old bug)
  if (
    await fileContains(
      `${home}/.tmux.nested.conf`,
      "source-file.*\\.tmux\\.conf$",
    )
  ) {
    fail(
      ".tmux.nested.conf sources .tmux.conf (should only source .tmux.shared.conf)",
    );
  } else {
    pass(".tmux.nested.conf does NOT source .tmux.conf");
  }

  // Outer should have explicit unbinds for nested keys
  if (await fileContains(`${home}/.tmux.conf`, "unbind.*C-M-S")) {
    pass(".tmux.conf has explicit unbinds for C-M-S-Arrow");
  } else {
    fail(
      ".tmux.conf missing unbinds for C-M-S-Arrow",
      "Stale bindings will persist across reloads",
    );
  }
}

async function checkOuterTmux() {
  section("Outer tmux Server");

  if (!(await tmuxServerRunning(OUTER_SOCKET))) {
    info("Outer tmux server not running — skipping server checks");
    return;
  }

  pass("Outer tmux server is running");

  // Extended keys
  const extKeys = await getTmuxOption(OUTER_SOCKET, "extended-keys", true);
  if (extKeys.includes("always")) {
    pass("extended-keys = always");
  } else {
    fail(`extended-keys = ${extKeys || "(not set)"}`, "Should be 'always'");
  }

  // Check C-M-Arrow bindings exist (outer window movement)
  const rootBindings = await getTmuxBindings(OUTER_SOCKET, "root");
  const hasOuterMove = rootBindings.some(
    (b) => b.includes("C-M-Left") && !b.includes("C-M-S"),
  );
  if (hasOuterMove) {
    pass("C-M-Arrow bindings present (outer window movement)");
  } else {
    fail("C-M-Arrow bindings missing — outer window movement won't work");
  }

  // Check C-M-S-Arrow bindings do NOT exist (those belong to nested)
  const hasStolenKeys = rootBindings.some((b) => b.includes("C-M-S-"));
  if (hasStolenKeys) {
    fail(
      "C-M-S-Arrow bindings found in OUTER tmux",
      "These intercept keys meant for nested tmux. Reload config or restart outer server.",
    );
  } else {
    pass("No C-M-S-Arrow bindings in outer (correct — those belong to nested)");
  }

  // Check C-o send-prefix exists
  const hasSendPrefix = rootBindings.some(
    (b) => b.includes("C-o") && b.includes("send-prefix"),
  );
  if (hasSendPrefix) {
    pass("C-o send-prefix binding present (prefix forwarding to nested)");
  } else {
    fail("C-o send-prefix missing — can't send prefix to nested tmux");
  }

  // Check prefix is C-x
  const prefix = await getTmuxOption(OUTER_SOCKET, "prefix");
  if (prefix.includes("C-x")) {
    pass("Prefix is C-x");
  } else {
    warn(`Prefix is ${prefix}`, "Expected C-x");
  }
}

async function checkNestedTmux() {
  section("Nested tmux Server");

  if (!(await tmuxServerRunning(NESTED_SOCKET))) {
    info("Nested tmux server not running — skipping server checks");
    return;
  }

  pass("Nested tmux server is running");

  // Extended keys
  const extKeys = await getTmuxOption(NESTED_SOCKET, "extended-keys", true);
  if (extKeys.includes("always")) {
    pass("extended-keys = always");
  } else {
    fail(`extended-keys = ${extKeys || "(not set)"}`, "Should be 'always'");
  }

  // Check C-M-S-Arrow bindings exist (nested window movement)
  const rootBindings = await getTmuxBindings(NESTED_SOCKET, "root");
  const hasNestedMove = rootBindings.some((b) => b.includes("C-M-S-Left"));
  if (hasNestedMove) {
    pass("C-M-S-Arrow bindings present (nested window movement)");
  } else {
    fail(
      "C-M-S-Arrow bindings missing in nested tmux",
      "Window movement in nested tmux won't work",
    );
  }

  // Check C-M-Arrow bindings do NOT exist in nested (those belong to outer)
  const hasOuterKeys = rootBindings.some(
    (b) => b.includes("C-M-Left") && !b.includes("C-M-S"),
  );
  if (hasOuterKeys) {
    fail(
      "C-M-Arrow bindings found in nested tmux (stale from old config)",
      "Reload nested config: tmux -L nested source-file ~/.tmux.nested.conf",
    );
  } else {
    pass("No C-M-Arrow bindings in nested (correct — those belong to outer)");
  }

  // Check nested doesn't have C-o send-prefix (only outer should)
  const hasSendPrefix = rootBindings.some(
    (b) => b.includes("C-o") && b.includes("send-prefix"),
  );
  if (hasSendPrefix) {
    fail(
      "C-o send-prefix found in nested tmux (stale from old config)",
      "Reload nested config: tmux -L nested source-file ~/.tmux.nested.conf",
    );
  } else {
    pass("No C-o send-prefix in nested (correct — only outer needs this)");
  }

  // Check prefix is C-x
  const prefix = await getTmuxOption(NESTED_SOCKET, "prefix");
  if (prefix.includes("C-x")) {
    pass("Prefix is C-x");
  } else {
    warn(`Prefix is ${prefix}`, "Expected C-x");
  }
}

async function checkToolsOnPath() {
  section("Tools on PATH");

  const swapScript = await run("which tmux-swap-or-move-window");
  if (swapScript) {
    pass(`tmux-swap-or-move-window found at ${swapScript}`);
  } else {
    fail("tmux-swap-or-move-window not on PATH");
  }

  const fzfPicker = await run("which tmux-fzf-picker");
  if (fzfPicker) {
    pass(`tmux-fzf-picker found at ${fzfPicker}`);
  } else {
    warn("tmux-fzf-picker not on PATH (FZF file picker won't work)");
  }

  const ic = await run("which ic");
  if (ic) {
    pass(`ic found at ${ic}`);
  } else {
    warn("ic not on PATH");
  }
}

async function checkGhosttyConfig() {
  section("Ghostty Terminal Config");

  const home = process.env.HOME || "/Users/benbernard";
  const ghosttyConfig = `${home}/.config/ghostty/config`;

  if (!(await fileExists(ghosttyConfig))) {
    info("Ghostty config not found — skipping");
    return;
  }

  // Check C-M-S-Arrow keybinds
  const expectedSequences: Record<string, string> = {
    "ctrl+alt+shift+arrow_left": "\\x1b[1;8D",
    "ctrl+alt+shift+arrow_right": "\\x1b[1;8C",
    "ctrl+alt+shift+arrow_up": "\\x1b[1;8A",
    "ctrl+alt+shift+arrow_down": "\\x1b[1;8B",
  };

  for (const [key, seq] of Object.entries(expectedSequences)) {
    if (await fileContains(ghosttyConfig, key)) {
      pass(`Ghostty keybind: ${key}`);
    } else {
      fail(`Ghostty missing keybind: ${key}`, `Should send ${seq}`);
    }
  }

  // Check Cmd+C keybind
  if (await fileContains(ghosttyConfig, "super+c")) {
    pass("Ghostty keybind: super+c (Cmd+C for copy)");
  } else {
    warn("Ghostty missing super+c keybind");
  }
}

async function checkKeyDeliveryChain() {
  section("Key Delivery Chain Summary");

  console.log(`
  ${BOLD}C-M-S-Arrow delivery path:${RESET}
    Ghostty  →  sends \\x1b[1;8{A,B,C,D}  (xterm modifier 8 = Ctrl+Alt+Shift)
       ↓
    Outer tmux  →  should NOT have C-M-S binding  →  passes key to pane
       ↓
    Nested tmux  →  has C-M-S-Arrow binding  →  runs tmux-swap-or-move-window

  ${BOLD}C-M-Arrow delivery path:${RESET}
    Ghostty  →  sends standard Ctrl+Alt+Arrow
       ↓
    Outer tmux  →  has C-M-Arrow binding  →  runs tmux-swap-or-move-window
       ↓
    (never reaches nested tmux)

  ${BOLD}Prefix delivery path:${RESET}
    C-x      →  outer tmux captures (prefix)
    C-o      →  outer tmux sends C-x to pane (via send-prefix)
    C-x C-o  →  sends literal C-o to terminal app
`);
}

// ──────────────────────────────────────────────────────────────────────────────
// Main
// ──────────────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`${BOLD}tmux Health Check${RESET}`);
  console.log("Verifying nested tmux keybinding chain...\n");

  await checkConfigFiles();
  await checkOuterTmux();
  await checkNestedTmux();
  await checkToolsOnPath();
  await checkGhosttyConfig();
  await checkKeyDeliveryChain();

  // Summary
  section("Results");
  console.log(`  ${GREEN}${passes} passed${RESET}`);
  if (warnings > 0) console.log(`  ${YELLOW}${warnings} warnings${RESET}`);
  if (failures > 0) console.log(`  ${RED}${failures} failures${RESET}`);

  if (failures > 0) {
    console.log(
      `\n${RED}${BOLD}Some checks failed.${RESET} Run 'tmux source-file ~/.tmux.conf' to reload outer config.`,
    );
    console.log(
      `If issues persist, kill both servers: 'tmux kill-server && tmux -L nested kill-server'`,
    );
    process.exit(1);
  } else if (warnings > 0) {
    console.log(
      `\n${YELLOW}All critical checks passed, but some warnings.${RESET}`,
    );
  } else {
    console.log(`\n${GREEN}${BOLD}All checks passed.${RESET}`);
  }
}

main();
