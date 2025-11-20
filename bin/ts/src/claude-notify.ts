#!/usr/bin/env tsx

import { execSync } from "child_process";
import { existsSync, readFileSync, writeFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { $ } from "zx";

// Silence zx command output by default
$.verbose = false;

interface NotificationState {
  last_type: string;
  timestamp: number;
}

const CLAUDE_ICON_BUNDLE = "com.anthropic.claudefordesktop";
const STATE_DIR = join(homedir(), ".claude");

async function main() {
  const notificationType = process.argv[2] || "unknown";

  // Get session identifier for per-session state tracking
  const sessionId =
    process.env.CLAUDE_SESSION_ID || process.ppid?.toString() || "default";
  const stateFile = join(STATE_DIR, `notification-state-${sessionId}`);
  const lockFile = `${stateFile}.lock`;

  // Clean up old state files (older than 7 days)
  try {
    await $`find ${STATE_DIR} -name 'notification-state-*' -type f -mtime +7 -delete`;
  } catch {
    // Ignore errors
  }

  // Get TMUX context
  const tmuxContext = await getTmuxContext();

  // Read last notification state
  const lastState = await readState(stateFile, lockFile);
  const lastType = lastState.last_type || "none";

  // Smart filtering logic:
  // If last notification was "stop" and current is "idle_prompt", skip it
  if (notificationType === "idle_prompt" && lastType === "stop") {
    // Skip notification but update state
    await writeState(stateFile, lockFile, notificationType);
    return;
  }

  // Prepare notification message and sound based on type
  let message: string;
  let sound: string;

  switch (notificationType) {
    case "idle_prompt":
      message = "Claude waiting for input";
      sound = "Basso";
      break;
    case "stop":
      message = "Claude stopped";
      sound = "Glass";
      break;
    default:
      message = "Claude notification";
      sound = "Basso";
  }

  // Add TMUX context to message if available
  if (tmuxContext) {
    message = `${message} [window: ${tmuxContext}]`;
  }

  // Send notification using terminal-notifier with Claude icon
  try {
    await $`terminal-notifier -message ${message} -sound ${sound} -sender ${CLAUDE_ICON_BUNDLE}`;
  } catch {
    // Ignore errors
  }

  // Update state
  await writeState(stateFile, lockFile, notificationType);
}

async function getTmuxContext(): Promise<string | null> {
  const tmux = process.env.TMUX;
  if (!tmux) {
    return null;
  }

  try {
    // Parse TMUX variable: /tmp/tmux-502/default,12345,0
    const socketPath = tmux.split(",")[0];
    const socketName = socketPath.split("/").pop() || "";

    // If we're in a nested TMUX session, query the outer session
    if (socketName === "nested") {
      // Get the outer tmux window name from the default socket
      const result = await $`tmux -L default display-message -p '#W'`;
      return result.stdout.trim();
    }

    // We're in the outer TMUX, get current window name
    const result = await $`tmux display-message -p '#W'`;
    return result.stdout.trim();
  } catch {
    return null;
  }
}

async function readState(
  stateFile: string,
  lockFile: string,
): Promise<NotificationState> {
  if (!existsSync(stateFile)) {
    return { last_type: "none", timestamp: 0 };
  }

  try {
    // Simple file read with timeout protection
    const content = readFileSync(stateFile, "utf-8");
    return JSON.parse(content) as NotificationState;
  } catch {
    return { last_type: "none", timestamp: 0 };
  }
}

async function writeState(
  stateFile: string,
  lockFile: string,
  notificationType: string,
): Promise<void> {
  const state: NotificationState = {
    last_type: notificationType,
    timestamp: Math.floor(Date.now() / 1000),
  };

  try {
    // Use atomic write with rename
    const tmpFile = `${stateFile}.tmp`;
    writeFileSync(tmpFile, JSON.stringify(state, null, 2));

    // Atomic rename
    try {
      execSync(`mv "${tmpFile}" "${stateFile}"`, { stdio: "ignore" });
    } catch {
      // Fallback to regular write
      writeFileSync(stateFile, JSON.stringify(state, null, 2));
    }
  } catch (error) {
    // Ignore write errors
  }
}

// Run main function
main().catch((error) => {
  console.error("Error in claude-notify:", error);
  process.exit(1);
});
