#!/usr/bin/env tsx

// Only emit verbose traces when explicitly enabled
const debugMode = process.env.CLAUDE_NOTIFY_DEBUG === "1";
const originalConsoleError = console.error.bind(console);
if (!debugMode) {
  console.error = (...args: unknown[]) => {
    const first = args[0];
    if (
      typeof first === "string" &&
      (first.startsWith("[TRACE]") || first.startsWith("[DEBUG]"))
    ) {
      return;
    }
    return originalConsoleError(...args);
  };
}

console.error("[TRACE] claude-notify.ts: Script started");

import { execSync } from "child_process";
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";

console.error("[TRACE] claude-notify.ts: Imports done, loading zx...");

import { $ } from "zx";

console.error("[TRACE] claude-notify.ts: zx loaded");

// Silence zx command output by default
$.verbose = false;

console.error("[TRACE] claude-notify.ts: Setup complete");

interface NotificationState {
  last_type: string;
  timestamp: number;
}

interface HookInput {
  // Common fields
  session_id?: string;
  transcript_path?: string;
  cwd?: string;
  permission_mode?: string;

  // Event-specific fields
  hook_event_name?: string;
  notification_type?: string;
  reason?: string;
  tool_name?: string;
  prompt?: string;
  message?: string;
  [key: string]: unknown; // Allow additional fields
}

const STATE_DIR = join(homedir(), ".claude");
const CACHE_DIR = join(homedir(), ".config", "claude-notify");
const CACHE_FILE = join(CACHE_DIR, "summaries.json");
const CLAUDE_PROJECTS_DIR = join(homedir(), ".claude", "projects");
const LOG_FILE = join(CACHE_DIR, "notifications.log");

const CLAUDE_ICON_BUNDLE = "com.anthropic.claudefordesktop";
const CODEX_SENDER_IDS = ["com.openai.chat"]; // ChatGPT bundle id on macOS
const CHATGPT_APP_ICON_PATHS = [
  "/Applications/ChatGPT.app/Contents/Resources/AppIcon.icns",
  join(
    homedir(),
    "Applications",
    "ChatGPT.app",
    "Contents",
    "Resources",
    "AppIcon.icns",
  ),
];
const CHATGPT_PNG_CACHE = join(CACHE_DIR, "chatgpt-icon.png");
const NEUTRAL_SENDER = "com.apple.Terminal";

function ensureChatGptPngIcon(): string | null {
  if (existsSync(CHATGPT_PNG_CACHE)) {
    return CHATGPT_PNG_CACHE;
  }

  const icnsPath = CHATGPT_APP_ICON_PATHS.find((p) => {
    try {
      return existsSync(p);
    } catch {
      return false;
    }
  });

  if (!icnsPath) return null;

  try {
    // Ensure cache dir exists
    if (!existsSync(CACHE_DIR)) {
      execSync(`mkdir -p "${CACHE_DIR}"`, { stdio: "ignore" });
    }
    // Convert icns to png (sips is available on macOS)
    execSync(
      `/usr/bin/sips -s format png "${icnsPath}" --out "${CHATGPT_PNG_CACHE}" >/dev/null`,
      { stdio: "ignore" },
    );
    if (existsSync(CHATGPT_PNG_CACHE)) return CHATGPT_PNG_CACHE;
  } catch {
    // ignore conversion failures
  }
  return null;
}

function getLastUserMessageFromSession(sessionFile: string): string | null {
  try {
    const content = readFileSync(sessionFile, "utf-8");
    const lines = content.split("\n").filter((line) => line.trim());

    for (let i = lines.length - 1; i >= 0; i--) {
      const line = lines[i];
      try {
        const entry = JSON.parse(line);
        if (
          entry.type === "user" &&
          !entry.isSidechain &&
          !entry.isMeta &&
          entry.message?.role === "user"
        ) {
          const messageContent = entry.message.content;

          if (typeof messageContent === "string") {
            if (
              messageContent.startsWith("<command-name>") ||
              messageContent.startsWith("<local-command-")
            ) {
              continue;
            }
            return messageContent;
          }

          if (Array.isArray(messageContent)) {
            const textParts = messageContent
              .filter((part: { type?: string }) => part.type === "text")
              .map((part: { text?: string }) => part.text);
            const text = textParts.join(" ");
            if (
              text.startsWith("<command-name>") ||
              text.startsWith("<local-command-")
            ) {
              continue;
            }
            return text;
          }
        }
      } catch {
        // Parse error, skip this line
      }
    }
  } catch {
    // ignore errors
  }
  return null;
}
function logToFile(message: string): void {
  try {
    // Ensure cache directory exists
    if (!existsSync(CACHE_DIR)) {
      execSync(`mkdir -p "${CACHE_DIR}"`, { stdio: "ignore" });
    }

    const timestamp = new Date().toISOString();
    const logEntry = `[${timestamp}] ${message}\n`;

    // Append to log file
    appendFileSync(LOG_FILE, logEntry);
  } catch (err) {
    // Surface logging errors in debug mode
    if (debugMode) {
      console.error("[DEBUG] logToFile error:", err);
    }
  }
}

async function readStdinJson(): Promise<HookInput | null> {
  console.error("[TRACE] readStdinJson: Starting");

  const debugMode = process.env.CLAUDE_NOTIFY_DEBUG === "1";

  console.error(`[TRACE] readStdinJson: stdin.isTTY = ${process.stdin.isTTY}`);

  if (debugMode) console.error("[DEBUG] readStdinJson: Starting");

  // Check if stdin has data
  if (process.stdin.isTTY) {
    console.error("[TRACE] readStdinJson: stdin is TTY, returning null");
    if (debugMode)
      console.error("[DEBUG] readStdinJson: stdin is TTY, returning null");
    return null;
  }

  console.error("[TRACE] readStdinJson: About to read from stdin...");

  if (debugMode) console.error("[DEBUG] readStdinJson: Reading from stdin...");

  return new Promise((resolve) => {
    console.error("[TRACE] readStdinJson: Inside Promise");

    const chunks: Buffer[] = [];
    let hasData = false;
    let isDone = false;

    console.error("[TRACE] readStdinJson: Setting up timeout (500ms)");

    // Set a short timeout - if no data arrives quickly, give up
    const timeout = setTimeout(() => {
      console.error("[TRACE] readStdinJson: Timeout fired!");
      if (!hasData && !isDone) {
        console.error(
          "[TRACE] readStdinJson: Timeout - no data received, cleaning up",
        );
        if (debugMode)
          console.error("[DEBUG] readStdinJson: Timeout - no data received");
        isDone = true;
        // Clean up listener
        process.stdin.removeAllListeners("data");
        process.stdin.removeAllListeners("end");
        process.stdin.pause();
        resolve(null);
      }
    }, 500); // 500ms timeout

    console.error("[TRACE] readStdinJson: Setting up data listener");

    process.stdin.on("data", (chunk) => {
      console.error(
        `[TRACE] readStdinJson: data event fired, chunk size: ${chunk.length}`,
      );
      if (isDone) return;
      hasData = true;
      if (debugMode)
        console.error(
          `[DEBUG] readStdinJson: Got chunk of ${chunk.length} bytes`,
        );
      chunks.push(chunk);
    });

    console.error("[TRACE] readStdinJson: Setting up end listener");

    process.stdin.on("end", () => {
      console.error("[TRACE] readStdinJson: end event fired");
      if (isDone) return;
      isDone = true;
      clearTimeout(timeout);

      if (debugMode)
        console.error("[DEBUG] readStdinJson: Finished reading chunks");

      // Clean up stdin
      process.stdin.removeAllListeners("data");
      process.stdin.removeAllListeners("end");
      process.stdin.pause();
      process.stdin.destroy();

      try {
        const input = Buffer.concat(chunks).toString("utf-8").trim();
        if (debugMode)
          console.error(
            `[DEBUG] readStdinJson: Got input (${input.length} chars)`,
          );

        if (!input) {
          if (debugMode) console.error("[DEBUG] readStdinJson: Empty input");
          resolve(null);
          return;
        }

        const parsed = JSON.parse(input) as HookInput;
        if (debugMode)
          console.error("[DEBUG] readStdinJson: Parsed JSON successfully");
        resolve(parsed);
      } catch (err) {
        if (debugMode) console.error(`[DEBUG] readStdinJson: Error - ${err}`);
        resolve(null);
      }
    });

    // Start reading
    console.error("[TRACE] readStdinJson: Calling process.stdin.resume()");
    process.stdin.resume();
    console.error(
      "[TRACE] readStdinJson: resume() called, waiting for events...",
    );
  });
}

async function main() {
  console.error("[TRACE] main: Entered main function");

  const cliArgs = process.argv.slice(2);
  const codexMode = cliArgs.includes("--codex");
  const filteredArgs = cliArgs.filter((arg) => arg !== "--codex");

  const tryParseJson = (raw: string | undefined): HookInput | null => {
    if (!raw) return null;
    const trimmed = raw.trim();
    if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) return null;
    try {
      return JSON.parse(trimmed) as HookInput;
    } catch {
      return null;
    }
  };

  console.error(`[TRACE] main: debugMode = ${debugMode}`);

  if (debugMode) console.error("[DEBUG] main: Starting claude-notify");
  if (debugMode)
    console.error(
      `[DEBUG] main: argv = ${JSON.stringify(
        process.argv,
      )}, codexMode=${codexMode}`,
    );
  if (debugMode)
    console.error(`[DEBUG] main: stdin.isTTY = ${process.stdin.isTTY}`);

  // In Codex mode, the payload is passed as a CLI arg (JSON string).
  // If that isn't present, also try stdin (some Codex hooks may still pipe JSON).
  // Otherwise, prefer stdin JSON (Claude desktop hook style).
  console.error("[TRACE] main: About to read hook input");
  let mergedHookInput: HookInput | null = null;
  if (codexMode) {
    mergedHookInput = tryParseJson(filteredArgs[0]) || null;
    if (mergedHookInput) {
      filteredArgs.shift();
    }
    if (!mergedHookInput) {
      mergedHookInput = await readStdinJson();
    }
  } else {
    mergedHookInput = await readStdinJson();
  }

  if (debugMode)
    console.error(
      `[DEBUG] main: hookInput = ${JSON.stringify(mergedHookInput)}`,
    );

  // If no stdin payload and no positional type, nothing to do
  if (!mergedHookInput && filteredArgs.length === 0) {
    logToFile("No hook input or notification type supplied; exiting.");
    return;
  }

  // Log hook input to file
  logToFile("=== New notification ===");
  logToFile(
    `Hook input (${codexMode ? "codex-cli" : "stdin"}): ${JSON.stringify(
      mergedHookInput,
      null,
      2,
    )}`,
  );
  logToFile(`argv: ${JSON.stringify(process.argv)}`);

  // Log all available fields in hookInput
  if (debugMode && mergedHookInput) {
    console.error("[DEBUG] main: hookInput fields:");
    for (const key of Object.keys(mergedHookInput)) {
      console.error(
        `[DEBUG] main:   ${key} = ${JSON.stringify(mergedHookInput[key])}`,
      );
    }
  }

  // Determine notification type from stdin or argv
  const notificationTypeRaw =
    mergedHookInput?.notification_type ||
    mergedHookInput?.hook_event_name ||
    // Codex notify may send a top-level event/type field
    (mergedHookInput as { event?: unknown })?.event ||
    (mergedHookInput as { type?: unknown })?.type ||
    filteredArgs[0] ||
    "unknown";
  const notificationType =
    typeof notificationTypeRaw === "string"
      ? notificationTypeRaw.toLowerCase()
      : notificationTypeRaw?.toString().toLowerCase() || "unknown";

  // Get transcript path and cwd from stdin if available
  const transcriptPath =
    mergedHookInput?.transcript_path ||
    (mergedHookInput as { transcript?: { path?: string } })?.transcript?.path ||
    (mergedHookInput as { session?: { transcript_path?: string } })?.session
      ?.transcript_path;
  const workingDir =
    mergedHookInput?.cwd ||
    (mergedHookInput as { workspace?: { current_dir?: string } })?.workspace
      ?.current_dir ||
    process.cwd();

  console.error("[TRACE] main: Determining notification type and paths");
  console.error(`[TRACE] main: workingDir = ${workingDir}`);

  // Get session identifier for per-session state tracking
  const sessionId =
    mergedHookInput?.session_id ||
    (mergedHookInput as { sessionId?: string })?.sessionId ||
    (mergedHookInput as { session?: { id?: string } })?.session?.id ||
    process.env.CLAUDE_SESSION_ID ||
    process.ppid?.toString() ||
    "default";
  const stateFile = join(STATE_DIR, `notification-state-${sessionId}`);
  const lockFile = `${stateFile}.lock`;

  console.error("[TRACE] main: About to clean up old state files");

  // Clean up old state files (older than 7 days)
  try {
    await $`find ${STATE_DIR} -name 'notification-state-*' -type f -mtime +7 -delete`;
  } catch {
    // Ignore errors
  }

  console.error("[TRACE] main: Cleaned up old state files");

  console.error("[TRACE] main: Checking if Claude is in active window");

  // Check if Claude is in the active window (both nested and outer if applicable)
  if (await isClaudeInActiveWindow()) {
    // Claude is visible, skip notification but update state
    console.error(
      "[TRACE] main: Claude is in active window, skipping notification",
    );
    logToFile("Action: Skipped (Claude in active window)");
    await writeState(stateFile, lockFile, notificationType);
    return;
  }

  console.error("[TRACE] main: Claude is not in active window, continuing");

  // Get project context (git directory basename)
  console.error("[TRACE] main: Getting project context");
  const projectContext = await getProjectContext(workingDir);
  console.error(`[TRACE] main: Project context = ${projectContext}`);

  console.error("[TRACE] main: Getting session summary");
  console.error(`[TRACE] main: transcriptPath = ${transcriptPath}`);

  // Get session summary (with timeout to keep notifications fast)
  let sessionSummary: string | null = null;
  if (transcriptPath) {
    // We have the exact transcript path from stdin!
    console.error("[TRACE] main: Using transcript path from stdin");
    try {
      // First check if summary exists in the file
      sessionSummary = await Promise.race([
        getSessionSummaryFromFile(transcriptPath),
        new Promise<null>((resolve) => setTimeout(() => resolve(null), 2000)),
      ]);

      // If no summary in file, try to generate one
      if (!sessionSummary && sessionId && sessionId !== "default") {
        console.error("[TRACE] main: No summary in file, checking cache");
        const cache = readCache();
        sessionSummary = cache[sessionId] || null;

        if (!sessionSummary) {
          console.error("[TRACE] main: No cached summary, generating new one");
          const firstMessage = getFirstUserMessage(transcriptPath);
          if (firstMessage) {
            const cleanMessage = firstMessage
              .replace(/<[^>]*>/g, "")
              .replace(/Caveat:.*/g, "")
              .trim();

            if (cleanMessage) {
              sessionSummary = await Promise.race([
                generateSummary(cleanMessage),
                new Promise<null>((resolve) =>
                  setTimeout(() => resolve(null), 2000),
                ),
              ]);

              if (sessionSummary) {
                // Cache the generated summary
                cache[sessionId] = sessionSummary;
                writeCache(cache);
                console.error(
                  "[TRACE] main: Generated and cached summary:",
                  sessionSummary,
                );
              }
            }
          }
        }
      }

      console.error(`[TRACE] main: Got session summary: ${sessionSummary}`);
    } catch (err) {
      console.error(`[TRACE] main: Error getting session summary: ${err}`);
      // Ignore errors
    }
  } else if (!codexMode && sessionId && sessionId !== "default") {
    // Fall back to finding the session file
    console.error("[TRACE] main: Falling back to finding session file");
    try {
      sessionSummary = await Promise.race([
        getSessionSummary(sessionId, workingDir),
        new Promise<null>((resolve) => setTimeout(() => resolve(null), 2000)),
      ]);
      console.error(`[TRACE] main: Got session summary: ${sessionSummary}`);
    } catch (err) {
      console.error(`[TRACE] main: Error getting session summary: ${err}`);
      // Ignore errors, use generic message
    }
  }

  console.error("[TRACE] main: Finished getting session summary");

  console.error("[TRACE] main: Reading last notification state");

  // Read last notification state
  const lastState = await readState(stateFile, lockFile);
  const lastType = (lastState.last_type || "none").toLowerCase();

  console.error(`[TRACE] main: lastType = ${lastType}`);

  // Smart filtering logic:
  // If last notification was "stop" and current is "idle_prompt", skip it
  if (notificationType === "idle_prompt" && lastType === "stop") {
    // Skip notification but update state
    console.error("[TRACE] main: Skipping idle_prompt after stop");
    logToFile("Action: Skipped (idle_prompt after stop)");
    await writeState(stateFile, lockFile, notificationType);
    return;
  }

  console.error("[TRACE] main: Preparing notification message");

  // Prepare notification message and sound based on type
  let message: string;
  let sound: string;
  const originLabel = codexMode ? "Codex" : "Claude";

  // Prefer the last user message in Codex agent turn payloads
  // Note: steve tried to use String() on an object here, which gives "[object Object]"
  // because apparently steve doesn't understand JavaScript type coercion. Fixed.
  const inputMessages = (mergedHookInput as { "input-messages"?: unknown })?.[
    "input-messages"
  ];
  const lastUserMessage =
    Array.isArray(inputMessages) && inputMessages.length > 0
      ? typeof inputMessages[inputMessages.length - 1] === "string"
        ? inputMessages[inputMessages.length - 1]
        : (inputMessages[inputMessages.length - 1] as { content?: string })
            ?.content ||
          (inputMessages[inputMessages.length - 1] as { text?: string })
            ?.text ||
          null
      : null;
  const lastTranscriptUser =
    transcriptPath && sessionId !== "default"
      ? getLastUserMessageFromSession(transcriptPath)
      : null;

  const inlineMessage =
    mergedHookInput?.message ||
    mergedHookInput?.prompt ||
    (mergedHookInput as { body?: string })?.body ||
    (mergedHookInput as { title?: string })?.title ||
    (mergedHookInput as { notification?: { message?: string; body?: string } })
      ?.notification?.message ||
    (mergedHookInput as { notification?: { message?: string; body?: string } })
      ?.notification?.body ||
    (mergedHookInput as { reason?: string })?.reason ||
    lastUserMessage ||
    lastTranscriptUser;

  const cleanedInline =
    typeof inlineMessage === "string"
      ? inlineMessage.replace(/\s+/g, " ").trim()
      : null;
  const bestInline = cleanedInline || lastTranscriptUser || null;

  const isCodexTurnComplete =
    codexMode &&
    ((mergedHookInput as { type?: string })?.type || "").toLowerCase() ===
      "agent-turn-complete";

  // steve had this backwards - we WANT to show the user's message, not bury it behind sessionSummary
  // Now with context prefixes so the user knows what's happening
  switch (notificationType) {
    case "idle_prompt":
      if (bestInline) {
        message = `Waiting: ${bestInline}`;
      } else if (sessionSummary) {
        message = `${sessionSummary} waiting`;
      } else {
        message = `${originLabel} waiting for input`;
      }
      sound = "Basso";
      break;
    case "stop":
      if (bestInline) {
        message = `Stopped: ${bestInline}`;
      } else if (sessionSummary) {
        message = `${sessionSummary} stopped`;
      } else {
        message = `${originLabel} stopped`;
      }
      sound = "Glass";
      break;
    default:
      if (isCodexTurnComplete) {
        message = bestInline
          ? `Complete: ${bestInline}`
          : `${originLabel} turn complete`;
      } else {
        message =
          bestInline ||
          (notificationType && notificationType !== "unknown"
            ? `${originLabel} ${notificationType}`
            : `${originLabel} notification`);
      }
      sound = "Basso";
  }

  // Add project context and origin label
  const projectLabel = projectContext ? `[${projectContext}] ` : "";
  message = `${originLabel} · ${projectLabel}${message}`;

  console.error(`[TRACE] main: Final message = ${message}`);
  console.error("[TRACE] main: Sending notification");

  // Escape leading bracket for terminal-notifier
  // terminal-notifier requires escaping the first character if it's a bracket
  const escapedMessage = message.startsWith("[") ? `\\${message}` : message;

  // Build terminal-notifier arguments with icon and sender
  // For Codex: use Terminal sender (NEUTRAL_SENDER) with ChatGPT icon
  // For Claude: use Claude bundle as sender
  const appIcon =
    codexMode &&
    CHATGPT_APP_ICON_PATHS.find((p) => {
      try {
        return existsSync(p);
      } catch {
        return false;
      }
    });

  const pngIcon = codexMode ? ensureChatGptPngIcon() : null;
  const contentImage = appIcon ? null : pngIcon;

  const args = [
    "-message",
    escapedMessage,
    "-sound",
    sound,
    "-title",
    originLabel,
  ];

  if (appIcon) {
    args.push("-appIcon", appIcon);
  } else if (contentImage) {
    args.push("-appIcon", contentImage);
    args.push("-contentImage", contentImage);
  }

  // Use transcript path as group ID if available (for per-session notification grouping)
  if (transcriptPath) {
    args.push("-group", transcriptPath);
  }

  // steve added a triple-nested retry loop with 2s timeouts per attempt.
  // That's 6 seconds of delay if all fail. For notifications. NOTIFICATIONS.
  // Notifications should be fast. This isn't a distributed transaction, steve.
  const sender = codexMode ? NEUTRAL_SENDER : CLAUDE_ICON_BUNDLE;
  args.push("-sender", sender);

  if (debugMode) {
    console.error(`[DEBUG] main: notification args = ${JSON.stringify(args)}`);
  }

  logToFile(`Notification type: ${notificationType}`);
  logToFile(`Project context: ${projectContext || "(none)"}`);
  logToFile(`Session summary: ${sessionSummary || "(none)"}`);
  logToFile(`Final message: ${message}`);
  logToFile(`Args: ${JSON.stringify(args)}`);

  try {
    await $`terminal-notifier ${args}`;
    console.error("[TRACE] main: Notification sent successfully");
    logToFile("Result: Success");
  } catch (err) {
    console.error(`[TRACE] main: Error sending notification: ${err}`);
    logToFile(`Result: Error - ${err}`);
    // Ignore errors
  }

  console.error("[TRACE] main: Updating state");

  // Update state
  await writeState(stateFile, lockFile, notificationType);

  console.error("[TRACE] main: Completed successfully");
}

async function isClaudeInActiveWindow(): Promise<boolean> {
  console.error("[TRACE] isClaudeInActiveWindow: Starting");

  // Check if we're in tmux at all
  const tmux = process.env.TMUX;
  console.error(`[TRACE] isClaudeInActiveWindow: TMUX env = ${tmux}`);

  if (!tmux) {
    // Not in tmux, can't determine, assume not active
    console.error(
      "[TRACE] isClaudeInActiveWindow: Not in tmux, returning false",
    );
    return false;
  }

  console.error(
    "[TRACE] isClaudeInActiveWindow: In tmux, checking window status",
  );

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
          const result =
            await $`tmux show-environment -g OUTER_TMUX_WINDOW 2>/dev/null`;
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

// Git helper functions
function findGitRoot(cwd: string): string | null {
  let currentDir = cwd;
  const root = "/";

  while (currentDir !== root) {
    const gitPath = join(currentDir, ".git");
    if (existsSync(gitPath)) {
      return currentDir;
    }
    const parentDir = join(currentDir, "..");
    if (parentDir === currentDir) {
      break;
    }
    currentDir = parentDir;
  }

  return null;
}

async function getProjectContext(cwd?: string): Promise<string | null> {
  const workingDir = cwd || process.cwd();
  const gitRoot = findGitRoot(workingDir);
  if (gitRoot) {
    return gitRoot.split("/").pop() || null;
  }
  return null;
}

// Cache functions
function readCache(): Record<string, string> {
  if (!existsSync(CACHE_FILE)) {
    return {};
  }

  try {
    const content = readFileSync(CACHE_FILE, "utf-8");
    return JSON.parse(content) as Record<string, string>;
  } catch {
    return {};
  }
}

function writeCache(cache: Record<string, string>): void {
  try {
    // Ensure cache directory exists
    if (!existsSync(CACHE_DIR)) {
      execSync(`mkdir -p "${CACHE_DIR}"`, { stdio: "ignore" });
    }

    const tmpFile = `${CACHE_FILE}.tmp`;
    writeFileSync(tmpFile, JSON.stringify(cache, null, 2));

    try {
      execSync(`mv "${tmpFile}" "${CACHE_FILE}"`, { stdio: "ignore" });
    } catch {
      writeFileSync(CACHE_FILE, JSON.stringify(cache, null, 2));
    }
  } catch {
    // Ignore write errors
  }
}

// Session file functions
function encodeProjectPath(path: string): string {
  return path.replace(/\//g, "-");
}

function findSessionFile(sessionId: string, cwd: string): string | null {
  const gitRoot = findGitRoot(cwd) || cwd;
  const encodedPath = encodeProjectPath(gitRoot);
  const projectDir = join(CLAUDE_PROJECTS_DIR, encodedPath);

  // If we have a real session ID (UUID format), try it first
  if (sessionId && sessionId !== "default" && sessionId.includes("-")) {
    const sessionFile = join(projectDir, `${sessionId}.jsonl`);
    if (existsSync(sessionFile)) {
      return sessionFile;
    }
  }

  // Otherwise, find the most recently modified session file in the project directory
  // This handles the case where CLAUDE_SESSION_ID isn't set
  if (!existsSync(projectDir)) {
    return null;
  }

  try {
    const { readdirSync, statSync } = require("fs");
    const files: Array<{ name: string; path: string; mtime: number }> =
      readdirSync(projectDir)
        .filter((f: string) => f.endsWith(".jsonl"))
        .map((f: string) => ({
          name: f,
          path: join(projectDir, f),
          mtime: statSync(join(projectDir, f)).mtime.getTime(),
        }))
        .sort(
          (
            a: { name: string; path: string; mtime: number },
            b: { name: string; path: string; mtime: number },
          ) => b.mtime - a.mtime,
        );

    if (files.length > 0) {
      return files[0].path;
    }
  } catch {
    // Ignore errors
  }

  return null;
}

function getSessionSummaryFromFile(sessionFile: string): string | null {
  try {
    const content = readFileSync(sessionFile, "utf-8");
    const lines = content.split("\n").filter((line) => line.trim());

    for (const line of lines) {
      try {
        const entry = JSON.parse(line);
        if (entry.type === "summary" && entry.summary) {
          return entry.summary;
        }
      } catch {}
    }
  } catch {
    // Ignore read errors
  }

  return null;
}

function getFirstUserMessage(sessionFile: string): string | null {
  try {
    const content = readFileSync(sessionFile, "utf-8");
    const lines = content.split("\n").filter((line) => line.trim());

    for (const line of lines) {
      try {
        const entry = JSON.parse(line);
        if (
          entry.type === "user" &&
          !entry.isSidechain &&
          !entry.isMeta &&
          entry.message?.role === "user"
        ) {
          const messageContent = entry.message.content;

          if (typeof messageContent === "string") {
            // Skip command messages and local command output
            if (
              messageContent.startsWith("<command-name>") ||
              messageContent.startsWith("<local-command-")
            ) {
              continue;
            }
            return messageContent;
          }

          if (Array.isArray(messageContent)) {
            const textParts = messageContent
              .filter((part) => part.type === "text")
              .map((part) => part.text);
            const text = textParts.join(" ");
            // Skip command messages
            if (
              text.startsWith("<command-name>") ||
              text.startsWith("<local-command-")
            ) {
              continue;
            }
            return text;
          }
        }
      } catch {}
    }
  } catch {
    // Ignore read errors
  }

  return null;
}

async function generateSummary(message: string): Promise<string | null> {
  try {
    const response = await fetch(
      "https://aigateway.instacart.tools/unified/benbernard-personal/v1/chat/completions",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model: "gpt-5-nano",
          reasoning_effort: "minimal",
          messages: [
            {
              role: "user",
              content: `Summarize this Claude Code session request in 3-8 words: "${message}"`,
            },
          ],
        }),
      },
    );

    if (response.ok) {
      const data = await response.json();
      const summary = data?.choices?.[0]?.message?.content;
      if (summary && typeof summary === "string") {
        return summary.trim();
      }
    }
  } catch {
    // Ignore API errors
  }

  return null;
}

async function getSessionSummary(
  sessionId: string,
  cwd: string,
): Promise<string | null> {
  // Check cache first
  const cache = readCache();
  if (cache[sessionId]) {
    return cache[sessionId];
  }

  // Find session file
  const sessionFile = findSessionFile(sessionId, cwd);
  if (!sessionFile) {
    return null;
  }

  // Check session file for existing summary
  const existingSummary = getSessionSummaryFromFile(sessionFile);
  if (existingSummary) {
    // Cache it for next time
    cache[sessionId] = existingSummary;
    writeCache(cache);
    return existingSummary;
  }

  // Try to generate summary via API (with timeout handled by caller)
  const firstMessage = getFirstUserMessage(sessionFile);
  if (!firstMessage) {
    return null;
  }

  // Clean up message - remove HTML tags and command markers
  const cleanMessage = firstMessage
    .replace(/<[^>]*>/g, "")
    .replace(/Caveat:.*/g, "")
    .trim();

  if (!cleanMessage) {
    return null;
  }

  // Generate summary via API
  const generatedSummary = await generateSummary(cleanMessage);
  if (generatedSummary) {
    // Cache it
    cache[sessionId] = generatedSummary;
    writeCache(cache);
    return generatedSummary;
  }

  return null;
}

// Run main function
console.error("[TRACE] claude-notify.ts: About to call main()");
main().catch((error) => {
  console.error("Error in claude-notify:", error);
  process.exit(1);
});
