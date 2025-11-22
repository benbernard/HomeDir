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

  // Check if Claude is in the active window (both nested and outer if applicable)
  if (await isClaudeInActiveWindow()) {
    // Claude is visible, skip notification but update state
    await writeState(stateFile, lockFile, notificationType);
    return;
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

  // Add TMUX context to message if available (put window name first)
  if (tmuxContext) {
    message = `[${tmuxContext}] ${message}`;
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

async function isClaudeInActiveWindow(): Promise<boolean> {
  // Check if we're in tmux at all
  const tmux = process.env.TMUX;
  if (!tmux) {
    // Not in tmux, can't determine, assume not active
    return false;
  }

  // Parse TMUX variable to detect nested session
  const socketPath = tmux.split(",")[0];
  const socketName = socketPath.split("/").pop() || "";

  // If we're in nested tmux
  if (socketName === "nested") {
    // Check if current nested window is active
    try {
      const nestedActive = await $`tmux display-message -p '#{window_active}'`;
      const isNestedActive = nestedActive.stdout.trim() === "1";

      if (!isNestedActive) {
        // Not in active nested window
        return false;
      }

      // Nested window is active, now check if outer window is active
      // Get the outer window name from global environment
      let outerWindowName: string | null = null;
      const envOuterWindow = process.env.OUTER_TMUX_WINDOW;
      if (envOuterWindow) {
        outerWindowName = envOuterWindow;
      } else {
        try {
          const result = await $`tmux show-environment -g OUTER_TMUX_WINDOW`;
          const match = result.stdout.match(/^OUTER_TMUX_WINDOW=(.+)$/m);
          if (match) {
            outerWindowName = match[1];
          }
        } catch {
          // Can't get outer window name
          return false;
        }
      }

      if (!outerWindowName) {
        // No outer window name available
        return false;
      }

      // Get currently active window name in outer tmux
      try {
        const outerActive = await $`tmux -L default display-message -p '#W'`;
        const activeOuterWindow = outerActive.stdout.trim();
        return activeOuterWindow === outerWindowName;
      } catch {
        return false;
      }
    } catch {
      return false;
    }
  }

  // We're in regular tmux, just check if current window is active
  try {
    const active = await $`tmux display-message -p '#{window_active}'`;
    return active.stdout.trim() === "1";
  } catch {
    return false;
  }
}

async function getTmuxContext(): Promise<string | null> {
  // Check if we're in tmux at all
  const tmux = process.env.TMUX;
  if (!tmux) {
    return null;
  }

  // Parse TMUX variable to detect nested session: /tmp/tmux-502/nested,12345,0
  const socketPath = tmux.split(",")[0];
  const socketName = socketPath.split("/").pop() || "";

  // If we're in nested tmux
  if (socketName === "nested") {
    // Get OUTER_TMUX_WINDOW from environment (set by nesttm function)
    const outerWindow = process.env.OUTER_TMUX_WINDOW;
    if (outerWindow) {
      return outerWindow;
    }
    // If not set, try to get it from tmux GLOBAL environment (-g flag)
    try {
      const result = await $`tmux show-environment -g OUTER_TMUX_WINDOW`;
      const match = result.stdout.match(/^OUTER_TMUX_WINDOW=(.+)$/m);
      if (match) {
        return match[1];
      }
    } catch {
      // Ignore errors
    }
    return null;
  }

  // We're in regular tmux, get current window name
  try {
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
