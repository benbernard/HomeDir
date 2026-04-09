import { homedir } from "os";
import { basename } from "path";

const DEFAULT_BODY = "Your latest Codex task is done.";
const MAX_PREVIEW_LENGTH = 140;
const GENERIC_COMPLETION_MESSAGES = new Set([
  "complete",
  "completed",
  "done",
  "done.",
  "finished",
  "ok",
  "ok.",
  "success",
  "success.",
]);

export interface CodexNotifyPayload {
  type?: string;
  cwd?: string;
  client?: string;
  "input-messages"?: unknown;
  "last-assistant-message"?: unknown;
  [key: string]: unknown;
}

export interface CodexNotificationContent {
  title: string;
  subtitle?: string;
  body: string;
  context: Record<string, string>;
}

export function parseCodexNotifyPayload(raw: string): CodexNotifyPayload {
  let parsed: unknown;

  try {
    parsed = JSON.parse(raw);
  } catch (error) {
    const detail =
      error instanceof Error ? error.message : "unknown JSON parse error";
    throw new Error(`Failed to parse Codex notification payload: ${detail}`);
  }

  if (parsed == null || Array.isArray(parsed) || typeof parsed !== "object") {
    throw new Error("Codex notification payload must be a JSON object.");
  }

  return parsed as CodexNotifyPayload;
}

export function buildCodexNotification(
  payload: CodexNotifyPayload,
): CodexNotificationContent {
  const cwd = normalizeText(payload.cwd);
  const assistantPreview = getUsefulAssistantPreview(
    payload["last-assistant-message"],
  );
  const inputPreview = getInputPreview(payload["input-messages"]);

  return {
    title: titleForEvent(payload.type),
    subtitle: subtitleForCwd(cwd),
    body:
      assistantPreview ??
      (inputPreview ? `Finished: ${inputPreview}` : DEFAULT_BODY),
    context: {
      client: normalizeText(payload.client) ?? "codex",
      cwd: cwd ?? homedir(),
      event_type: normalizeText(payload.type) ?? "unknown",
    },
  };
}

function titleForEvent(type: string | undefined): string {
  const normalizedType = normalizeText(type);

  switch (normalizedType) {
    case "agent-turn-complete":
      return "Codex finished";
    case undefined:
      return "Codex update";
    default:
      return `Codex ${humanizeEventType(normalizedType)}`;
  }
}

function subtitleForCwd(cwd: string | undefined): string | undefined {
  if (!cwd) {
    return undefined;
  }

  const cwdName = basename(cwd);
  const homeName = basename(homedir());
  if (!cwdName || cwdName === "/" || cwdName === "." || cwdName === homeName) {
    return undefined;
  }

  return cwdName;
}

function getUsefulAssistantPreview(value: unknown): string | undefined {
  const preview = truncate(normalizeText(value));
  if (!preview) {
    return undefined;
  }

  return GENERIC_COMPLETION_MESSAGES.has(preview.toLowerCase())
    ? undefined
    : preview;
}

function getInputPreview(value: unknown): string | undefined {
  if (!Array.isArray(value)) {
    return undefined;
  }

  for (let index = value.length - 1; index >= 0; index -= 1) {
    const preview = truncate(normalizeText(value[index]));
    if (preview) {
      return preview;
    }
  }

  return undefined;
}

function humanizeEventType(value: string): string {
  return value
    .split("-")
    .filter(Boolean)
    .map((part, index) =>
      index === 0 ? part[0].toUpperCase() + part.slice(1) : part.toLowerCase(),
    )
    .join(" ");
}

function normalizeText(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const normalized = value.replace(/\s+/g, " ").trim();
  return normalized.length > 0 ? normalized : undefined;
}

function truncate(value: string | undefined): string | undefined {
  if (!value) {
    return undefined;
  }

  if (value.length <= MAX_PREVIEW_LENGTH) {
    return value;
  }

  return `${value.slice(0, MAX_PREVIEW_LENGTH - 1).trimEnd()}…`;
}
