#!/usr/bin/env tsx

import { spawn, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import {
  chmodSync,
  closeSync,
  createWriteStream,
  existsSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  watch,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { finished } from "node:stream/promises";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import {
  type FsActivityKind,
  classifyFsUsageLine,
  lineMentionsExactPath,
  lineMentionsPathWithinDirectory,
  lineMentionsTargetFamily,
} from "./lib/fs-usage";

const DEFAULT_TARGET = join(homedir(), ".claude", "settings.json");
const DEFAULT_STATE_DIR = join(
  homedir(),
  ".local",
  "state",
  "claude-settings-traces",
);

function timestampForPath(date = new Date()): string {
  return date.toISOString().replaceAll(":", "-").replaceAll(".", "-");
}

function sha256(content: Buffer): string {
  return createHash("sha256").update(content).digest("hex");
}

function writePrivateFile(path: string, content: string | Buffer): void {
  const fd = openSync(path, "w", 0o600);
  try {
    writeFileSync(fd, content);
  } finally {
    closeSync(fd);
  }
  chmodSync(path, 0o600);
}

function captureCommand(path: string, command: string, args: string[]): void {
  const result = spawnSync(command, args, { encoding: "utf8" });
  const output = [result.stdout, result.stderr].filter(Boolean).join("");
  writePrivateFile(path, output);
}

async function main(): Promise<void> {
  const argv = await yargs(hideBin(process.argv))
    .scriptName("trace-claude-settings")
    .option("target", {
      alias: "t",
      type: "string",
      default: DEFAULT_TARGET,
      description: "Settings file to monitor",
    })
    .option("output", {
      alias: "o",
      type: "string",
      description:
        "Output directory (a timestamped state directory by default)",
    })
    .help()
    .alias("help", "h")
    .example("$0", "Trace ~/.claude/settings.json until Ctrl-C")
    .example(
      "$0 -o ~/Desktop/claude-trace",
      "Write the trace to a specific directory",
    )
    .parse();

  if (process.platform !== "darwin") {
    console.error(
      "trace-claude-settings requires macOS and /usr/bin/fs_usage.",
    );
    process.exitCode = 1;
    return;
  }

  const target = resolve(argv.target.replace(/^~(?=\/)/, homedir()));
  const targetDirectory = dirname(target);
  const outputDirectory = resolve(
    argv.output
      ? argv.output.replace(/^~(?=\/)/, homedir())
      : join(DEFAULT_STATE_DIR, timestampForPath()),
  );

  if (!existsSync(targetDirectory)) {
    console.error(`Target directory does not exist: ${targetDirectory}`);
    process.exitCode = 1;
    return;
  }

  if (existsSync(outputDirectory) && readdirSync(outputDirectory).length > 0) {
    console.error(`Output directory is not empty: ${outputDirectory}`);
    console.error(
      "Choose a new directory so an earlier trace is not overwritten.",
    );
    process.exitCode = 1;
    return;
  }

  mkdirSync(outputDirectory, { recursive: true, mode: 0o700 });
  chmodSync(outputDirectory, 0o700);
  mkdirSync(join(outputDirectory, "changes"), {
    recursive: true,
    mode: 0o700,
  });
  chmodSync(join(outputDirectory, "changes"), 0o700);

  const relatedLogPath = join(outputDirectory, "fs-usage.related.log");
  const eventLogPath = join(outputDirectory, "fs-usage.events.log");
  const writeLogPath = join(outputDirectory, "fs-usage.write-events.log");
  const stderrLogPath = join(outputDirectory, "fs-usage.stderr.log");
  const observationLogPath = join(outputDirectory, "observations.jsonl");
  const relatedLog = createWriteStream(relatedLogPath, { mode: 0o600 });
  const eventLog = createWriteStream(eventLogPath, { mode: 0o600 });
  const writeLog = createWriteStream(writeLogPath, { mode: 0o600 });
  const stderrLog = createWriteStream(stderrLogPath, { mode: 0o600 });
  const observationLog = createWriteStream(observationLogPath, { mode: 0o600 });
  const startedAt = new Date();

  writePrivateFile(
    join(outputDirectory, "run.json"),
    `${JSON.stringify(
      {
        target,
        outputDirectory,
        startedAt: startedAt.toISOString(),
        command: process.argv,
        hostname: process.env.HOSTNAME ?? null,
        platform: process.platform,
        arch: process.arch,
      },
      null,
      2,
    )}\n`,
  );
  captureCommand(join(outputDirectory, "processes.before.txt"), "/bin/ps", [
    "-axo",
    "pid=,ppid=,user=,lstart=,command=",
  ]);
  captureCommand(join(outputDirectory, "directory.before.txt"), "/bin/ls", [
    "-laT",
    targetDirectory,
  ]);

  let observationNumber = 0;
  let lastObservedState: string | undefined;

  const observeTarget = (
    trigger: string,
    changedName?: string | null,
  ): void => {
    const observedAt = new Date();
    let content: Buffer | undefined;
    let state = "missing";

    try {
      content = readFileSync(target);
      state = sha256(content);
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code;
      if (code !== "ENOENT") {
        observationLog.write(
          `${JSON.stringify({
            observedAt: observedAt.toISOString(),
            trigger,
            changedName,
            error: String(error),
          })}\n`,
        );
        return;
      }
    }

    if (state === lastObservedState) return;

    observationNumber += 1;
    lastObservedState = state;
    const stateFile = content
      ? join(
          outputDirectory,
          "changes",
          `${String(observationNumber).padStart(3, "0")}-${timestampForPath(
            observedAt,
          )}.json`,
        )
      : null;

    if (content && stateFile) writePrivateFile(stateFile, content);
    observationLog.write(
      `${JSON.stringify({
        observedAt: observedAt.toISOString(),
        trigger,
        changedName,
        state,
        stateFile,
      })}\n`,
    );
    console.log(
      `[${observedAt.toISOString()}] observed settings state ${state.slice(
        0,
        12,
      )}`,
    );
  };

  observeTarget("initial");
  const beforeContent = existsSync(target) ? readFileSync(target) : undefined;
  if (beforeContent) {
    writePrivateFile(
      join(outputDirectory, "settings.before.json"),
      beforeContent,
    );
  }

  let observationTimer: NodeJS.Timeout | undefined;
  const directoryWatcher = watch(targetDirectory, (eventType, filename) => {
    const changedName = filename?.toString() ?? null;
    if (observationTimer) clearTimeout(observationTimer);
    observationTimer = setTimeout(
      () => observeTarget(`fs.watch:${eventType}`, changedName),
      30,
    );
  });

  console.log(`Trace output: ${outputDirectory}`);
  console.log(`Watching:    ${target}`);
  console.log("Requesting sudo access for fs_usage...");

  const sudoCheck = spawnSync("/usr/bin/sudo", ["-v"], { stdio: "inherit" });
  if (sudoCheck.status !== 0) {
    directoryWatcher.close();
    relatedLog.end();
    eventLog.end();
    writeLog.end();
    stderrLog.end();
    observationLog.end();
    console.error(
      "Could not obtain sudo access. No filesystem trace was started.",
    );
    process.exitCode = 1;
    return;
  }

  console.log(
    "Tracing filesystem activity. Press Ctrl-C to stop and summarize.\n",
  );

  const tracer = spawn(
    "/usr/bin/sudo",
    ["/usr/bin/fs_usage", "-w", "-f", "filesys"],
    {
      detached: true,
      stdio: ["ignore", "pipe", "pipe"],
    },
  );

  let pendingOutput = "";
  let eventCount = 0;
  let relatedEventCount = 0;
  let relatedWriteCount = 0;
  let relatedLogBackpressured = false;
  const activityCounts: Record<FsActivityKind, number> = {
    metadata: 0,
    read: 0,
    write: 0,
    other: 0,
  };
  const candidateCounts = new Map<string, number>();

  const handleLine = (line: string): void => {
    if (!line.includes(targetDirectory)) return;

    const activity = classifyFsUsageLine(line);
    const mentionsExactTarget = lineMentionsExactPath(line, target);
    const mentionsTargetFamily = lineMentionsTargetFamily(line, target);
    const isDirectoryWrite =
      activity === "write" &&
      lineMentionsPathWithinDirectory(line, targetDirectory);

    if (!mentionsTargetFamily && !isDirectoryWrite) return;

    relatedEventCount += 1;
    if (activity === "write") relatedWriteCount += 1;
    const labeledLine = `[${activity}] ${line}`;
    if (!relatedLog.write(`${labeledLine}\n`) && !relatedLogBackpressured) {
      relatedLogBackpressured = true;
      tracer.stdout.pause();
      relatedLog.once("drain", () => {
        relatedLogBackpressured = false;
        tracer.stdout.resume();
      });
    }

    const processColumn = line.trim().split(/\s+/).at(-1);
    if (processColumn) {
      const candidate = processColumn.replace(/\.\d+$/, "");
      candidateCounts.set(candidate, (candidateCounts.get(candidate) ?? 0) + 1);
    }

    if (mentionsExactTarget) {
      eventCount += 1;
      activityCounts[activity] += 1;
      eventLog.write(`${labeledLine}\n`);
      console.log(labeledLine);
    } else if (activity === "write") {
      console.log(`[related write] ${line}`);
    }

    if (activity === "write") writeLog.write(`${line}\n`);
  };

  tracer.stdout.on("data", (chunk: Buffer) => {
    pendingOutput += chunk.toString("utf8");
    const lines = pendingOutput.split("\n");
    pendingOutput = lines.pop() ?? "";
    for (const line of lines) handleLine(line);
  });
  tracer.stderr.pipe(stderrLog);

  let finalizing = false;
  const finalize = async (reason: string, exitCode = 0): Promise<void> => {
    if (finalizing) return;
    finalizing = true;
    process.removeAllListeners("SIGINT");
    process.removeAllListeners("SIGTERM");
    console.log(`\nStopping trace (${reason})...`);

    directoryWatcher.close();
    if (observationTimer) clearTimeout(observationTimer);

    if (tracer.pid && tracer.exitCode === null && tracer.signalCode === null) {
      spawnSync(
        "/usr/bin/sudo",
        ["/bin/kill", "-s", "INT", "--", `-${tracer.pid}`],
        { stdio: "ignore" },
      );
      await Promise.race([
        new Promise<void>((resolveExit) =>
          tracer.once("exit", () => resolveExit()),
        ),
        new Promise<void>((resolveTimeout) => setTimeout(resolveTimeout, 1500)),
      ]);
    }

    if (tracer.pid && tracer.exitCode === null && tracer.signalCode === null) {
      spawnSync(
        "/usr/bin/sudo",
        ["/bin/kill", "-s", "TERM", "--", `-${tracer.pid}`],
        { stdio: "ignore" },
      );
      await Promise.race([
        new Promise<void>((resolveExit) =>
          tracer.once("exit", () => resolveExit()),
        ),
        new Promise<void>((resolveTimeout) => setTimeout(resolveTimeout, 1000)),
      ]);
    }

    if (tracer.pid && tracer.exitCode === null && tracer.signalCode === null) {
      spawnSync(
        "/usr/bin/sudo",
        ["/bin/kill", "-s", "KILL", "--", `-${tracer.pid}`],
        { stdio: "ignore" },
      );
    }

    if (pendingOutput) handleLine(pendingOutput);
    observeTarget("final");

    const afterContent = existsSync(target) ? readFileSync(target) : undefined;
    if (afterContent) {
      writePrivateFile(
        join(outputDirectory, "settings.after.json"),
        afterContent,
      );
    }

    captureCommand(join(outputDirectory, "processes.after.txt"), "/bin/ps", [
      "-axo",
      "pid=,ppid=,user=,lstart=,command=",
    ]);
    captureCommand(join(outputDirectory, "directory.after.txt"), "/bin/ls", [
      "-laT",
      targetDirectory,
    ]);

    const beforePath = join(outputDirectory, "settings.before.json");
    const afterPath = join(outputDirectory, "settings.after.json");
    if (existsSync(beforePath) && existsSync(afterPath)) {
      captureCommand(join(outputDirectory, "settings.diff"), "/usr/bin/diff", [
        "-u",
        beforePath,
        afterPath,
      ]);
    } else {
      writePrivateFile(
        join(outputDirectory, "settings.diff"),
        "A unified diff could not be produced because the file was missing at the start or end.\n",
      );
    }

    const candidateSummary = [...candidateCounts.entries()]
      .sort((left, right) => right[1] - left[1])
      .map(([candidate, count]) => `  ${candidate}: ${count} matching events`);
    const summary = [
      "Claude settings trace",
      `Started: ${startedAt.toISOString()}`,
      `Stopped: ${new Date().toISOString()}`,
      `Reason: ${reason}`,
      `Target: ${target}`,
      `Exact-target fs_usage events: ${eventCount}`,
      `  writes: ${activityCounts.write}`,
      `  reads: ${activityCounts.read}`,
      `  metadata checks: ${activityCounts.metadata}`,
      `  other: ${activityCounts.other}`,
      `Related filesystem events retained: ${relatedEventCount}`,
      `Related write events: ${relatedWriteCount}`,
      `Distinct observed states: ${observationNumber}`,
      `Observed content changes after initial state: ${Math.max(
        0,
        observationNumber - 1,
      )}`,
      "Candidate process names (the numeric fs_usage suffix is a thread ID):",
      ...(candidateSummary.length > 0 ? candidateSummary : ["  none observed"]),
      "",
      "Files:",
      "  fs-usage.events.log        labeled activity for the exact target",
      "  fs-usage.write-events.log  target-family and target-directory writes",
      "  fs-usage.related.log       exact target, temp-family, and directory writes",
      "  observations.jsonl         timestamps and hashes for distinct settings states",
      "  changes/                   preserved settings states",
      "  settings.diff              initial-to-final unified diff",
      "  processes.*.txt            process inventories for attribution",
      "  directory.*.txt            directory metadata before and after",
      "",
      "Warning: snapshots and process command lines may contain secrets. The trace directory is owner-only.",
      "",
    ].join("\n");
    writePrivateFile(join(outputDirectory, "SUMMARY.txt"), summary);

    relatedLog.end();
    eventLog.end();
    writeLog.end();
    stderrLog.end();
    observationLog.end();
    await Promise.allSettled([
      finished(relatedLog),
      finished(eventLog),
      finished(writeLog),
      finished(stderrLog),
      finished(observationLog),
    ]);

    console.log(summary);
    console.log(`Saved trace: ${outputDirectory}`);
    process.exitCode = exitCode;
  };

  process.once("SIGINT", () => void finalize("SIGINT (Ctrl-C)"));
  process.once("SIGTERM", () => void finalize("SIGTERM", 1));
  tracer.once("error", (error) => {
    console.error(`fs_usage failed to start: ${error}`);
    void finalize("fs_usage start failure", 1);
  });
  tracer.once("exit", (code, signal) => {
    if (!finalizing) {
      void finalize(
        `fs_usage exited (code=${code}, signal=${signal})`,
        code ?? 1,
      );
    }
  });
}

void main();
