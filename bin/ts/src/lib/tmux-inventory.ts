import { execFileSync } from "child_process";
import {
  closeSync,
  existsSync,
  linkSync,
  mkdirSync,
  openSync,
  readFileSync,
  readSync,
  readdirSync,
  renameSync,
  statSync,
  unlinkSync,
  writeFileSync,
} from "fs";
import { homedir } from "os";
import { basename, dirname, join } from "path";

export const DEFAULT_OUTER_SOCKET = "default";
export const DEFAULT_NESTED_SOCKET = "nested";
export const DEFAULT_WATCH_INTERVAL_SECONDS = 10;

const SCHEMA_VERSION = 1;
const FIELD_SEPARATOR = String.fromCharCode(31);
const RECENT_SESSION_MAX_AGE_MS = 24 * 60 * 60 * 1000;
const MAX_RECENT_CODEX_DAYS = 3;
const WATCHER_LOCK_NAME = "tmux-inventory.watcher.lock";
const STALE_LOCK_MAX_AGE_MS = 60 * 1000;
const INVENTORY_FILE_NAME = "tmux-inventory.json";

export type AgentName = "claude" | "codex" | "pi" | "opencode";
export type OuterWindowKind = "plain" | "nested" | "ic";

export interface AgentState {
  name: AgentName;
  pid: number;
  command: string;
  sessionId?: string;
  sessionIdSource?: string;
}

export interface TmuxPaneSnapshot {
  paneId: string;
  paneIndex: number;
  pid: number;
  tty: string;
  command: string;
  title: string;
  directory: string;
  active: boolean;
  agents: AgentState[];
}

export interface TmuxWindowSnapshot {
  windowId: string;
  windowIndex: number;
  windowName: string;
  active: boolean;
  kind: OuterWindowKind;
  currentDirectory: string;
  nestedSessionNames: string[];
  panes: TmuxPaneSnapshot[];
}

export interface TmuxSessionSnapshot {
  sessionId: string;
  sessionName: string;
  attached: boolean;
  windows: TmuxWindowSnapshot[];
}

export interface TmuxAttachment {
  outerSessionId: string;
  outerSessionName: string;
  outerWindowId: string;
  outerWindowIndex: number;
  outerWindowName: string;
  outerPaneId: string;
  nestedSessionId: string;
  nestedSessionName: string;
  nestedClientPid: number;
  nestedClientTty: string;
}

export interface TmuxInventory {
  schemaVersion: 1;
  updatedAt: string;
  outerSocket: string;
  nestedSocket: string;
  outer: TmuxSessionSnapshot[];
  nested: TmuxSessionSnapshot[];
  attachments: TmuxAttachment[];
}

interface RawSession {
  sessionId: string;
  sessionName: string;
  attached: boolean;
}

interface RawWindow {
  sessionId: string;
  sessionName: string;
  windowId: string;
  windowIndex: number;
  windowName: string;
  active: boolean;
}

interface RawPane {
  sessionId: string;
  windowId: string;
  paneId: string;
  paneIndex: number;
  pid: number;
  tty: string;
  command: string;
  title: string;
  directory: string;
  active: boolean;
}

interface RawClient {
  clientPid: number;
  clientTty: string;
  sessionId: string;
  sessionName: string;
}

export interface AgentProcess {
  command: string;
  args: string;
}

interface ProcessInfo extends AgentProcess {
  pid: number;
  ppid: number;
}

interface ServerSnapshot {
  sessions: TmuxSessionSnapshot[];
  windowByKey: Map<string, TmuxWindowSnapshot>;
  paneById: Map<string, TmuxPaneSnapshot>;
  paneProcesses: Map<string, ProcessInfo[]>;
}

interface SessionCandidate {
  id: string;
  source: string;
}

export interface InventoryFormatOptions {
  includeNested?: boolean;
  homeDirectory?: string;
}

export interface InventoryRefreshOptions {
  outerSocket?: string;
  nestedSocket?: string;
  now?: Date;
  statePath?: string;
}

export interface InventoryWatcherOptions {
  outerSocket?: string;
  nestedSocket?: string;
  intervalSeconds?: number;
  quiet?: boolean;
  statePath?: string;
}

function runCommand(command: string, args: string[]): string | null {
  try {
    const output = execFileSync(command, args, {
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "ignore"],
    });
    return output;
  } catch {
    return null;
  }
}

function runTmux(socket: string, args: string[]): string {
  return runCommand("tmux", ["-L", socket, ...args])?.trimEnd() ?? "";
}

function parseRows(output: string, fieldCount: number): string[][] {
  if (!output.trim()) return [];

  return output
    .split(/\r?\n/)
    .filter((line) => line.length > 0)
    .map((line) => {
      const fields = line.split(FIELD_SEPARATOR);
      while (fields.length < fieldCount) fields.push("");
      return fields;
    });
}

function parseBoolean(value: string): boolean {
  return value === "1" || value.toLowerCase() === "true";
}

function parseNumber(value: string): number {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

function listSessions(socket: string): RawSession[] {
  const format = [
    "#{session_id}",
    "#{session_name}",
    "#{session_attached}",
  ].join(FIELD_SEPARATOR);

  return parseRows(runTmux(socket, ["list-sessions", "-F", format]), 3).map(
    ([sessionId, sessionName, attached]) => ({
      sessionId,
      sessionName,
      attached: parseBoolean(attached),
    }),
  );
}

function listWindows(socket: string): RawWindow[] {
  const format = [
    "#{session_id}",
    "#{session_name}",
    "#{window_id}",
    "#{window_index}",
    "#{window_name}",
    "#{window_active}",
  ].join(FIELD_SEPARATOR);

  return parseRows(
    runTmux(socket, ["list-windows", "-a", "-F", format]),
    6,
  ).map(
    ([sessionId, sessionName, windowId, windowIndex, windowName, active]) => ({
      sessionId,
      sessionName,
      windowId,
      windowIndex: parseNumber(windowIndex),
      windowName,
      active: parseBoolean(active),
    }),
  );
}

function listPanes(socket: string): RawPane[] {
  const format = [
    "#{session_id}",
    "#{window_id}",
    "#{pane_id}",
    "#{pane_index}",
    "#{pane_pid}",
    "#{pane_tty}",
    "#{pane_current_command}",
    "#{pane_title}",
    "#{pane_current_path}",
    "#{pane_active}",
  ].join(FIELD_SEPARATOR);

  return parseRows(runTmux(socket, ["list-panes", "-a", "-F", format]), 10).map(
    ([
      sessionId,
      windowId,
      paneId,
      paneIndex,
      pid,
      tty,
      command,
      title,
      directory,
      active,
    ]) => ({
      sessionId,
      windowId,
      paneId,
      paneIndex: parseNumber(paneIndex),
      pid: parseNumber(pid),
      tty,
      command,
      title,
      directory,
      active: parseBoolean(active),
    }),
  );
}

function listClients(socket: string): RawClient[] {
  const format = [
    "#{client_pid}",
    "#{client_tty}",
    "#{session_id}",
    "#{session_name}",
  ].join(FIELD_SEPARATOR);

  return parseRows(runTmux(socket, ["list-clients", "-F", format]), 4).map(
    ([clientPid, clientTty, sessionId, sessionName]) => ({
      clientPid: parseNumber(clientPid),
      clientTty,
      sessionId,
      sessionName,
    }),
  );
}

function readProcessTable(): ProcessInfo[] {
  const output = runCommand("ps", ["-axo", "pid=,ppid=,comm=,args="]);
  if (!output) return [];

  const processes: ProcessInfo[] = [];
  for (const line of output.split(/\r?\n/)) {
    const match = line.match(/^\s*(\d+)\s+(\d+)\s+(\S+)(?:\s+(.*))?$/);
    if (!match) continue;

    processes.push({
      pid: Number.parseInt(match[1], 10),
      ppid: Number.parseInt(match[2], 10),
      command: match[3],
      args: match[4] ?? "",
    });
  }

  return processes;
}

function buildChildrenByParent(
  processes: ProcessInfo[],
): Map<number, ProcessInfo[]> {
  const children = new Map<number, ProcessInfo[]>();
  for (const process of processes) {
    const siblings = children.get(process.ppid) ?? [];
    siblings.push(process);
    children.set(process.ppid, siblings);
  }
  return children;
}

function processTree(
  rootPid: number,
  childrenByParent: Map<number, ProcessInfo[]>,
  processByPid: Map<number, ProcessInfo>,
): ProcessInfo[] {
  if (!rootPid) return [];

  const result: ProcessInfo[] = [];
  const queue = [rootPid];
  const visited = new Set<number>();

  while (queue.length > 0) {
    const pid = queue.shift();
    if (pid === undefined || visited.has(pid)) continue;
    visited.add(pid);

    const process = processByPid.get(pid);
    if (process) result.push(process);

    for (const child of childrenByParent.get(pid) ?? []) {
      queue.push(child.pid);
    }
  }

  return result;
}

function hasWord(text: string, word: string): boolean {
  const escaped = word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(?:^|[\\s/])${escaped}(?:$|[\\s/])`, "i").test(text);
}

export function identifyAgentProcess(process: AgentProcess): AgentName | null {
  const executable = basename(process.command).toLowerCase();
  const text = `${process.command} ${process.args}`.toLowerCase();

  if (
    executable === "claude" ||
    text.includes("@anthropic-ai/claude-code") ||
    hasWord(text, "claude-code")
  ) {
    return "claude";
  }

  if (
    executable === "codex" ||
    executable === "codex-cli" ||
    text.includes("@openai/codex") ||
    hasWord(text, "codex-cli")
  ) {
    return "codex";
  }

  if (
    executable === "pi" ||
    executable === "pi-coding-agent" ||
    text.includes("pi-coding-agent") ||
    text.includes("@mariozechner/pi")
  ) {
    return "pi";
  }

  if (
    executable === "opencode" ||
    executable === "opencode-ai" ||
    text.includes("opencode-ai")
  ) {
    return "opencode";
  }

  return null;
}

function readProcessEnvironment(pid: number): Record<string, string> {
  const output = runCommand("ps", ["eww", "-p", String(pid), "-o", "command="]);
  if (!output) return {};

  const environment: Record<string, string> = {};
  const keys = [
    "CLAUDE_SESSION_ID",
    "CODEX_SESSION_ID",
    "CODEX_THREAD_ID",
    "PI_SESSION_ID",
    "OPENCODE_SESSION_ID",
    "OPENCODE_SESSION",
  ];

  for (const key of keys) {
    const match = output.match(new RegExp(`(?:^|\\s)${key}=([^\\s]+)`));
    if (match?.[1]) environment[key] = match[1];
  }

  return environment;
}

function sessionIdFromText(text: string): string | undefined {
  const labeled = text.match(
    /(?:session[_-]?id|thread[_-]?id|conversation[_-]?id|--session)\s*[=: ]\s*([A-Za-z0-9_.-]+)/i,
  );
  if (labeled?.[1]) return labeled[1].replace(/[),;]+$/, "");

  const opencodeId = text.match(/\bses_[A-Za-z0-9]+\b/);
  if (opencodeId?.[0]) return opencodeId[0];

  const uuid = text.match(
    /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i,
  );
  return uuid?.[0];
}

function encodeProjectPath(path: string): string {
  return path.replace(/\//g, "-");
}

function encodePiSessionDirectory(path: string): string {
  return `--${path.replace(/^\/+/, "").replace(/\//g, "-")}--`;
}

function readFirstLine(path: string): string | null {
  let fd: number | undefined;
  try {
    fd = openSync(path, "r");
    const buffer = Buffer.alloc(4096);
    const bytesRead = readSync(fd, buffer, 0, buffer.length, 0);
    return buffer.subarray(0, bytesRead).toString("utf8").split(/\r?\n/, 1)[0];
  } catch {
    return null;
  } finally {
    if (fd !== undefined) closeSync(fd);
  }
}

function sessionMetadataFromFile(
  path: string,
  fallbackId: string,
): { id: string; cwd?: string } {
  const firstLine = readFirstLine(path);
  if (firstLine) {
    try {
      const parsed = JSON.parse(firstLine) as {
        id?: unknown;
        cwd?: unknown;
        payload?: { id?: unknown; session_id?: unknown; cwd?: unknown };
      };
      const id =
        (typeof parsed.id === "string" && parsed.id) ||
        (typeof parsed.payload?.id === "string" && parsed.payload.id) ||
        (typeof parsed.payload?.session_id === "string" &&
          parsed.payload.session_id) ||
        fallbackId;
      const cwd =
        (typeof parsed.cwd === "string" && parsed.cwd) ||
        (typeof parsed.payload?.cwd === "string" && parsed.payload.cwd) ||
        undefined;
      return { id, cwd };
    } catch {
      // Fall back to the filename when the session file is not JSONL metadata.
    }
  }

  return { id: fallbackId };
}

function pathsMatch(left: string | undefined, right: string): boolean {
  if (!left) return false;
  const normalizedLeft = left.replace(/\/$/, "");
  const normalizedRight = right.replace(/\/$/, "");
  return (
    normalizedLeft === normalizedRight ||
    normalizedLeft.startsWith(`${normalizedRight}/`) ||
    normalizedRight.startsWith(`${normalizedLeft}/`)
  );
}

function latestSessionInDirectory(
  directory: string,
  currentDirectory: string,
  now: number,
  source: string,
): SessionCandidate | undefined {
  if (!existsSync(directory)) return undefined;

  let files: string[];
  try {
    files = readdirSync(directory)
      .filter((name) => name.endsWith(".jsonl"))
      .map((name) => join(directory, name))
      .filter((path) => {
        try {
          return now - statSync(path).mtimeMs <= RECENT_SESSION_MAX_AGE_MS;
        } catch {
          return false;
        }
      })
      .sort((left, right) => statSync(right).mtimeMs - statSync(left).mtimeMs);
  } catch {
    return undefined;
  }

  for (const path of files) {
    const fallbackId = basename(path, ".jsonl").replace(/^rollout-[^-]+-/, "");
    const metadata = sessionMetadataFromFile(path, fallbackId);
    if (!metadata.cwd || pathsMatch(metadata.cwd, currentDirectory)) {
      return { id: metadata.id, source };
    }
  }

  return undefined;
}

function latestCodexSession(
  currentDirectory: string,
  now: number,
): SessionCandidate | undefined {
  const root = join(homedir(), ".codex", "sessions");
  const candidates: string[] = [];

  for (let offset = 0; offset < MAX_RECENT_CODEX_DAYS; offset += 1) {
    const date = new Date(now - offset * 24 * 60 * 60 * 1000);
    const directory = join(
      root,
      String(date.getUTCFullYear()).padStart(4, "0"),
      String(date.getUTCMonth() + 1).padStart(2, "0"),
      String(date.getUTCDate()).padStart(2, "0"),
    );
    if (!existsSync(directory)) continue;

    try {
      for (const name of readdirSync(directory)) {
        if (name.startsWith("rollout-") && name.endsWith(".jsonl")) {
          candidates.push(join(directory, name));
        }
      }
    } catch {
      // Ignore an unavailable day directory.
    }
  }

  candidates.sort((left, right) => {
    try {
      return statSync(right).mtimeMs - statSync(left).mtimeMs;
    } catch {
      return 0;
    }
  });

  for (const path of candidates) {
    try {
      if (now - statSync(path).mtimeMs > RECENT_SESSION_MAX_AGE_MS) continue;
    } catch {
      continue;
    }

    const fallbackId = basename(path)
      .replace(/^rollout-/, "")
      .replace(/\.jsonl$/, "")
      .replace(/^.*_/, "");
    const metadata = sessionMetadataFromFile(path, fallbackId);
    if (!metadata.cwd || pathsMatch(metadata.cwd, currentDirectory)) {
      return { id: metadata.id, source: "codex-session-file" };
    }
  }

  return undefined;
}

function resolveGitRoot(directory: string): string {
  return (
    runCommand("git", [
      "-C",
      directory,
      "rev-parse",
      "--show-toplevel",
    ])?.trim() || directory
  );
}

function latestClaudeSession(
  currentDirectory: string,
  now: number,
): SessionCandidate | undefined {
  const projectRoot = resolveGitRoot(currentDirectory);
  return latestSessionInDirectory(
    join(homedir(), ".claude", "projects", encodeProjectPath(projectRoot)),
    currentDirectory,
    now,
    "claude-session-file",
  );
}

function latestPiSession(
  currentDirectory: string,
  now: number,
): SessionCandidate | undefined {
  return latestSessionInDirectory(
    join(
      homedir(),
      ".pi",
      "agent",
      "sessions",
      encodePiSessionDirectory(currentDirectory),
    ),
    currentDirectory,
    now,
    "pi-session-file",
  );
}

function latestOpenCodeSession(
  currentDirectory: string,
  now: number,
): SessionCandidate | undefined {
  const databasePath = join(
    homedir(),
    ".local",
    "share",
    "opencode",
    "opencode.db",
  );
  if (!existsSync(databasePath)) return undefined;

  const directory = resolveGitRoot(currentDirectory).replace(/'/g, "''");
  const query = `SELECT id || char(9) || time_updated FROM session WHERE directory = '${directory}' ORDER BY time_updated DESC LIMIT 1;`;
  const output = runCommand("sqlite3", [
    "-batch",
    "-noheader",
    databasePath,
    query,
  ]);
  if (!output?.trim()) return undefined;

  const [id, updatedAt] = output.trim().split(/\r?\n/, 1)[0].split("\t");
  const updatedTimestamp = Number(updatedAt);
  if (!id || !Number.isFinite(updatedTimestamp)) return undefined;
  if (now - updatedTimestamp > RECENT_SESSION_MAX_AGE_MS) return undefined;

  return { id, source: "opencode-database" };
}

function findAgentSession(
  name: AgentName,
  process: ProcessInfo,
  directory: string,
  now: number,
): SessionCandidate | undefined {
  const environment = readProcessEnvironment(process.pid);
  const environmentKeys: Record<AgentName, string[]> = {
    claude: ["CLAUDE_SESSION_ID"],
    codex: ["CODEX_SESSION_ID", "CODEX_THREAD_ID"],
    pi: ["PI_SESSION_ID"],
    opencode: ["OPENCODE_SESSION_ID", "OPENCODE_SESSION"],
  };

  for (const key of environmentKeys[name]) {
    if (environment[key])
      return { id: environment[key], source: "environment" };
  }

  const commandLineId = sessionIdFromText(process.args);
  if (commandLineId) return { id: commandLineId, source: "command-line" };

  switch (name) {
    case "claude":
      return latestClaudeSession(directory, now);
    case "codex":
      return latestCodexSession(directory, now);
    case "pi":
      return latestPiSession(directory, now);
    case "opencode":
      return latestOpenCodeSession(directory, now);
  }
}

function detectAgents(
  processes: ProcessInfo[],
  directory: string,
  now: number,
  title: string,
): AgentState[] {
  const agents: AgentState[] = [];
  const seen = new Set<string>();

  for (const process of processes) {
    const name = identifyAgentProcess(process);
    if (!name || seen.has(`${name}:${process.pid}`)) continue;
    seen.add(`${name}:${process.pid}`);

    const session = findAgentSession(name, process, directory, now);
    agents.push({
      name,
      pid: process.pid,
      command: basename(process.command),
      ...(session
        ? { sessionId: session.id, sessionIdSource: session.source }
        : {}),
    });
  }

  if (
    agents.every((agent) => agent.name !== "pi") &&
    /^π(?:\s|$)/u.test(title)
  ) {
    const piProcess =
      processes.find(
        (process) =>
          basename(process.command) === "bun" && process.args.includes("/omp"),
      ) ?? processes[0];
    if (piProcess) {
      const session = latestPiSession(directory, now);
      agents.push({
        name: "pi",
        pid: piProcess.pid,
        command: "pi",
        ...(session
          ? {
              sessionId: session.id,
              sessionIdSource: "pi-title-session-file",
            }
          : {}),
      });
    }
  }

  return agents;
}

function serverWindowKey(sessionId: string, windowId: string): string {
  return `${sessionId}:${windowId}`;
}

function collectServer(
  socket: string,
  processes: ProcessInfo[],
  now: number,
): ServerSnapshot {
  const rawSessions = listSessions(socket);
  const rawWindows = listWindows(socket);
  const rawPanes = listPanes(socket);
  const processByPid = new Map(
    processes.map((process) => [process.pid, process]),
  );
  const childrenByParent = buildChildrenByParent(processes);
  const sessions = rawSessions.map<TmuxSessionSnapshot>((session) => ({
    sessionId: session.sessionId,
    sessionName: session.sessionName,
    attached: session.attached,
    windows: [],
  }));
  const sessionById = new Map(
    sessions.map((session) => [session.sessionId, session]),
  );
  const windowByKey = new Map<string, TmuxWindowSnapshot>();
  const paneById = new Map<string, TmuxPaneSnapshot>();
  const paneProcesses = new Map<string, ProcessInfo[]>();

  for (const rawWindow of rawWindows) {
    const session = sessionById.get(rawWindow.sessionId);
    if (!session) continue;

    const window: TmuxWindowSnapshot = {
      windowId: rawWindow.windowId,
      windowIndex: rawWindow.windowIndex,
      windowName: rawWindow.windowName,
      active: rawWindow.active,
      kind: "plain",
      currentDirectory: "",
      nestedSessionNames: [],
      panes: [],
    };
    session.windows.push(window);
    windowByKey.set(
      serverWindowKey(rawWindow.sessionId, rawWindow.windowId),
      window,
    );
  }

  for (const rawPane of rawPanes) {
    const window = windowByKey.get(
      serverWindowKey(rawPane.sessionId, rawPane.windowId),
    );
    if (!window) continue;

    const processesForPane = processTree(
      rawPane.pid,
      childrenByParent,
      processByPid,
    );
    const pane: TmuxPaneSnapshot = {
      paneId: rawPane.paneId,
      paneIndex: rawPane.paneIndex,
      pid: rawPane.pid,
      tty: rawPane.tty,
      command: rawPane.command,
      title: rawPane.title,
      directory: rawPane.directory,
      active: rawPane.active,
      agents: detectAgents(
        processesForPane,
        rawPane.directory,
        now,
        rawPane.title,
      ),
    };
    window.panes.push(pane);
    paneById.set(rawPane.paneId, pane);
    paneProcesses.set(rawPane.paneId, processesForPane);
  }

  for (const session of sessions) {
    session.windows.sort((left, right) => left.windowIndex - right.windowIndex);
    for (const window of session.windows) {
      window.panes.sort((left, right) => left.paneIndex - right.paneIndex);
      const activePane =
        window.panes.find((pane) => pane.active) ?? window.panes[0];
      window.currentDirectory = activePane?.directory ?? "";
    }
  }

  return { sessions, windowByKey, paneById, paneProcesses };
}

function findOuterPaneForClient(
  client: RawClient,
  outer: ServerSnapshot,
):
  | {
      pane: TmuxPaneSnapshot;
      window: TmuxWindowSnapshot;
      session: TmuxSessionSnapshot;
    }
  | undefined {
  for (const session of outer.sessions) {
    for (const window of session.windows) {
      for (const pane of window.panes) {
        if (pane.tty && pane.tty === client.clientTty) {
          return { pane, window, session };
        }
      }
    }
  }

  for (const [paneId, processes] of outer.paneProcesses) {
    if (!processes.some((process) => process.pid === client.clientPid))
      continue;
    const pane = outer.paneById.get(paneId);
    if (!pane) continue;

    for (const session of outer.sessions) {
      const window = session.windows.find((candidate) =>
        candidate.panes.some(
          (candidatePane) => candidatePane.paneId === paneId,
        ),
      );
      if (window) return { pane, window, session };
    }
  }

  return undefined;
}

function nestedSessionCurrentDirectory(session: TmuxSessionSnapshot): string {
  const activeWindow = session.windows.find((window) => window.active);
  return (
    activeWindow?.currentDirectory ?? session.windows[0]?.currentDirectory ?? ""
  );
}

function classifyOuterWindow(window: TmuxWindowSnapshot): OuterWindowKind {
  if (window.nestedSessionNames.some((name) => name.startsWith("ic_"))) {
    return "ic";
  }
  if (window.nestedSessionNames.length > 0) return "nested";
  if (window.windowName.startsWith("ic:")) return "ic";
  return "plain";
}

export function collectTmuxInventory(
  options: InventoryRefreshOptions = {},
): TmuxInventory {
  const outerSocket = options.outerSocket ?? DEFAULT_OUTER_SOCKET;
  const nestedSocket = options.nestedSocket ?? DEFAULT_NESTED_SOCKET;
  const now = options.now ?? new Date();
  const processTable = readProcessTable();
  const outer = collectServer(outerSocket, processTable, now.getTime());
  const nested = collectServer(nestedSocket, processTable, now.getTime());
  const nestedSessionsById = new Map(
    nested.sessions.map((session) => [session.sessionId, session]),
  );
  const attachments: TmuxAttachment[] = [];

  for (const client of listClients(nestedSocket)) {
    const nestedSession = nestedSessionsById.get(client.sessionId);
    if (!nestedSession) continue;

    const outerMatch = findOuterPaneForClient(client, outer);
    if (!outerMatch) continue;

    const { pane, window, session } = outerMatch;
    const nestedDirectory = nestedSessionCurrentDirectory(nestedSession);
    if (nestedDirectory) {
      pane.directory = nestedDirectory;
      if (pane.active) window.currentDirectory = nestedDirectory;
    }
    if (!window.nestedSessionNames.includes(nestedSession.sessionName)) {
      window.nestedSessionNames.push(nestedSession.sessionName);
    }
    window.kind = classifyOuterWindow(window);

    attachments.push({
      outerSessionId: session.sessionId,
      outerSessionName: session.sessionName,
      outerWindowId: window.windowId,
      outerWindowIndex: window.windowIndex,
      outerWindowName: window.windowName,
      outerPaneId: pane.paneId,
      nestedSessionId: nestedSession.sessionId,
      nestedSessionName: nestedSession.sessionName,
      nestedClientPid: client.clientPid,
      nestedClientTty: client.clientTty,
    });
  }

  for (const session of outer.sessions) {
    for (const window of session.windows) {
      window.kind = classifyOuterWindow(window);
    }
  }

  return {
    schemaVersion: SCHEMA_VERSION,
    updatedAt: now.toISOString(),
    outerSocket,
    nestedSocket,
    outer: outer.sessions,
    nested: nested.sessions,
    attachments,
  };
}

export function getInventoryStateDirectory(): string {
  const stateHome =
    process.env.XDG_STATE_HOME?.trim() || join(homedir(), ".local", "state");
  return join(stateHome, "ic");
}

export function getInventoryStatePath(): string {
  return join(getInventoryStateDirectory(), INVENTORY_FILE_NAME);
}

function getWatcherLockPath(statePath = getInventoryStatePath()): string {
  return join(dirname(statePath), WATCHER_LOCK_NAME);
}

export function readTmuxInventory(
  path = getInventoryStatePath(),
): TmuxInventory | null {
  if (!existsSync(path)) return null;

  try {
    const parsed = JSON.parse(readFileSync(path, "utf8")) as TmuxInventory;
    if (parsed.schemaVersion !== SCHEMA_VERSION || !parsed.updatedAt)
      return null;
    return parsed;
  } catch {
    return null;
  }
}

export function writeTmuxInventory(
  inventory: TmuxInventory,
  path = getInventoryStatePath(),
): void {
  mkdirSync(dirname(path), { recursive: true });
  const temporaryPath = `${path}.${process.pid}.tmp`;
  writeFileSync(
    temporaryPath,
    `${JSON.stringify(inventory, null, 2)}\n`,
    "utf8",
  );
  renameSync(temporaryPath, path);
}

export function refreshTmuxInventory(
  options: InventoryRefreshOptions = {},
): TmuxInventory {
  const inventory = collectTmuxInventory(options);
  const statePath = options.statePath ?? getInventoryStatePath();
  if (inventory.outer.length === 0) {
    const previous = readTmuxInventory(statePath);
    if (previous) return previous;
  }

  writeTmuxInventory(inventory, statePath);
  return inventory;
}

function tryCreateWatcherLock(path: string): boolean {
  const temporaryPath = `${path}.${process.pid}.${Date.now()}.tmp`;
  try {
    writeFileSync(temporaryPath, `${process.pid}\n`, {
      encoding: "utf8",
      flag: "wx",
    });
    linkSync(temporaryPath, path);
    return true;
  } catch {
    return false;
  } finally {
    try {
      unlinkSync(temporaryPath);
    } catch {
      // The temporary file may already have been removed.
    }
  }
}

function isWatcherLockOld(path: string): boolean {
  try {
    return Date.now() - statSync(path).mtimeMs > STALE_LOCK_MAX_AGE_MS;
  } catch {
    return false;
  }
}

function quarantineStaleWatcherLock(
  path: string,
  observedContents: string,
): boolean {
  const quarantinePath = `${path}.${process.pid}.${Date.now()}.stale`;
  try {
    renameSync(path, quarantinePath);
  } catch {
    return false;
  }

  try {
    if (readFileSync(quarantinePath, "utf8") !== observedContents) {
      try {
        linkSync(quarantinePath, path);
      } catch {
        // Another watcher may have installed a new lock already.
      } finally {
        try {
          unlinkSync(quarantinePath);
        } catch {
          // The quarantine file may already be gone.
        }
      }
      return false;
    }
    unlinkSync(quarantinePath);
    return true;
  } catch {
    return false;
  }
}

function acquireWatcherLock(statePath = getInventoryStatePath()): boolean {
  const path = getWatcherLockPath(statePath);
  mkdirSync(dirname(path), { recursive: true });

  if (tryCreateWatcherLock(path)) return true;

  let observedContents: string;
  try {
    observedContents = readFileSync(path, "utf8");
  } catch {
    return false;
  }

  const pid = Number.parseInt(observedContents.trim(), 10);
  if (pid > 0) {
    try {
      process.kill(pid, 0);
      return false;
    } catch {
      // The recorded owner is gone; claim the stale lock below.
    }
  } else if (!isWatcherLockOld(path)) {
    // Do not remove a lock while its owner may still be writing its PID.
    return false;
  }

  if (!quarantineStaleWatcherLock(path, observedContents)) return false;
  return tryCreateWatcherLock(path);
}

function releaseWatcherLock(statePath = getInventoryStatePath()): void {
  const path = getWatcherLockPath(statePath);
  try {
    const pid = Number.parseInt(readFileSync(path, "utf8").trim(), 10);
    if (pid === process.pid) unlinkSync(path);
  } catch {
    // The lock may have been cleaned up by a stale-lock recovery.
  }
}

export async function runTmuxInventoryWatcher(
  options: InventoryWatcherOptions = {},
): Promise<void> {
  const statePath = options.statePath ?? getInventoryStatePath();
  if (!acquireWatcherLock(statePath)) return;

  const intervalSeconds = Math.max(
    1,
    options.intervalSeconds ?? DEFAULT_WATCH_INTERVAL_SECONDS,
  );
  const intervalMs = intervalSeconds * 1000;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let finished = false;

  await new Promise<void>((resolve) => {
    const finish = () => {
      if (finished) return;
      finished = true;
      if (timer) {
        clearTimeout(timer);
        timer = undefined;
      }
      process.off("SIGINT", finish);
      process.off("SIGTERM", finish);
      releaseWatcherLock(statePath);
      resolve();
    };

    const tick = () => {
      if (finished) return;

      try {
        const liveInventory = collectTmuxInventory({
          outerSocket: options.outerSocket,
          nestedSocket: options.nestedSocket,
        });
        if (liveInventory.outer.length === 0) {
          finish();
          return;
        }

        writeTmuxInventory(liveInventory, statePath);
        if (!options.quiet) {
          console.log(`tmux inventory refreshed at ${liveInventory.updatedAt}`);
        }
      } catch {
        // A transient tmux restart should not take down the watcher.
      }

      timer = setTimeout(tick, intervalMs);
    };

    process.once("SIGINT", finish);
    process.once("SIGTERM", finish);
    tick();
  });
}

function shortenPath(path: string, homeDirectory: string): string {
  if (path === homeDirectory) return "~";
  if (path.startsWith(`${homeDirectory}/`)) {
    return `~/${path.slice(homeDirectory.length + 1)}`;
  }
  return path || "?";
}

function formatAge(updatedAt: string, now: number): string {
  const ageSeconds = Math.max(
    0,
    Math.floor((now - Date.parse(updatedAt)) / 1000),
  );
  if (ageSeconds < 2) return "just now";
  if (ageSeconds < 60) return `${ageSeconds}s ago`;
  if (ageSeconds < 3600) return `${Math.floor(ageSeconds / 60)}m ago`;
  return `${Math.floor(ageSeconds / 3600)}h ago`;
}

function formatAgent(agent: AgentState): string {
  const session = agent.sessionId ? ` ${agent.sessionId}` : " session-id=?";
  return `${agent.name}${session}`;
}

export function formatTmuxInventory(
  inventory: TmuxInventory,
  options: InventoryFormatOptions = {},
): string {
  const homeDirectory = options.homeDirectory ?? homedir();
  const now = Date.now();
  const lines = [
    `Tmux inventory — refreshed ${formatAge(inventory.updatedAt, now)}`,
    `State: ${getInventoryStatePath()}`,
    "",
    "Outer tmux",
  ];

  if (inventory.outer.length === 0) {
    lines.push("  No active outer tmux sessions found.");
  }

  for (const session of inventory.outer) {
    lines.push(
      `  ${session.sessionName} (${session.sessionId})${
        session.attached ? " [attached]" : ""
      }`,
    );
    for (const window of session.windows) {
      const nested = window.nestedSessionNames.length
        ? ` -> ${window.nestedSessionNames.join(", ")}`
        : "";
      lines.push(
        `    ${window.windowIndex}: ${window.windowName || "(unnamed)"} ${
          window.windowId
        } [${window.kind}]${window.active ? " *" : ""}${nested}`,
      );
      lines.push(
        `      dir: ${shortenPath(window.currentDirectory, homeDirectory)}`,
      );
      for (const pane of window.panes) {
        if (pane.agents.length === 0 && window.panes.length === 1) continue;
        const agents = pane.agents.length
          ? ` agents: ${pane.agents.map(formatAgent).join(", ")}`
          : "";
        lines.push(
          `      pane ${pane.paneId} ${pane.command || "?"} ${shortenPath(
            pane.directory,
            homeDirectory,
          )}${pane.active ? " *" : ""}${agents}`,
        );
      }
    }
  }

  if (options.includeNested !== false) {
    lines.push("", "Nested tmux sessions");
    if (inventory.nested.length === 0) {
      lines.push("  No nested tmux sessions found.");
    }
    for (const session of inventory.nested) {
      const attachments = inventory.attachments.filter(
        (attachment) => attachment.nestedSessionId === session.sessionId,
      );
      const attachedTo = attachments.length
        ? ` -> ${attachments
            .map(
              (attachment) =>
                `${attachment.outerSessionName}:${attachment.outerWindowIndex}`,
            )
            .join(", ")}`
        : "";
      lines.push(
        `  ${session.sessionName} (${session.sessionId})${
          session.attached ? " [attached]" : ""
        }${attachedTo}`,
      );
      for (const window of session.windows) {
        lines.push(
          `    ${window.windowIndex}: ${window.windowName || "(unnamed)"} ${
            window.windowId
          }${window.active ? " *" : ""} dir: ${shortenPath(
            window.currentDirectory,
            homeDirectory,
          )}`,
        );
        for (const pane of window.panes) {
          for (const agent of pane.agents) {
            lines.push(
              `      pane ${pane.paneId} agent: ${formatAgent(agent)}`,
            );
          }
        }
      }
    }
  }

  if (inventory.attachments.length > 0) {
    lines.push("", "Mappings");
    for (const attachment of inventory.attachments) {
      lines.push(
        `  ${attachment.outerSessionName}:${attachment.outerWindowIndex} ${attachment.outerWindowId} ${attachment.outerWindowName} -> ${attachment.nestedSessionName} (pane ${attachment.outerPaneId})`,
      );
    }
  }

  return `${lines.join("\n")}\n`;
}
