#!/usr/bin/env node

import { join } from "path";
import { readFile, readdir, stat } from "fs/promises";
import pLimit from "p-limit";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

interface Stats {
  filesRead: number;
  directoriesScanned: number;
  bytesRead: number;
  errors: number;
  startTime: number;
  currentFile: string;
}

interface Options {
  path: string;
  concurrency: number;
  skipHidden: boolean;
  maxDepth?: number;
}

// ANSI escape codes for terminal manipulation
const CLEAR_LINE = "\x1b[2K";
const MOVE_TO_START = "\r";
const HIDE_CURSOR = "\x1b[?25l";
const SHOW_CURSOR = "\x1b[?25h";
const SAVE_CURSOR = "\x1b7";
const RESTORE_CURSOR = "\x1b8";

class ProgressDisplay {
  private stats: Stats;
  private updateInterval: NodeJS.Timeout | null = null;
  private lastUpdate = 0;
  private readonly UPDATE_THROTTLE_MS = 50; // Update max every 50ms

  constructor() {
    this.stats = {
      filesRead: 0,
      directoriesScanned: 0,
      bytesRead: 0,
      errors: 0,
      startTime: Date.now(),
      currentFile: "",
    };

    // Hide cursor for cleaner output
    process.stdout.write(HIDE_CURSOR);

    // Ensure cursor is shown on exit
    process.on("exit", () => {
      process.stdout.write(SHOW_CURSOR);
    });
    process.on("SIGINT", () => {
      process.stdout.write(SHOW_CURSOR);
      process.exit(0);
    });
  }

  updateStats(update: Partial<Stats>) {
    Object.assign(this.stats, update);
    this.throttledRender();
  }

  private throttledRender() {
    const now = Date.now();
    if (now - this.lastUpdate >= this.UPDATE_THROTTLE_MS) {
      this.render();
      this.lastUpdate = now;
    }
  }

  private formatBytes(bytes: number): string {
    const units = ["B", "KB", "MB", "GB", "TB"];
    let size = bytes;
    let unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return `${size.toFixed(2)} ${units[unitIndex]}`;
  }

  private formatNumber(num: number): string {
    return num.toLocaleString();
  }

  private formatDuration(ms: number): string {
    const seconds = Math.floor(ms / 1000);
    const minutes = Math.floor(seconds / 60);
    const hours = Math.floor(minutes / 60);

    if (hours > 0) {
      return `${hours}h ${minutes % 60}m ${seconds % 60}s`;
    }
    if (minutes > 0) {
      return `${minutes}m ${seconds % 60}s`;
    }
    return `${seconds}s`;
  }

  private truncatePath(path: string, maxLength: number): string {
    if (path.length <= maxLength) return path;
    return `...${path.slice(-(maxLength - 3))}`;
  }

  private render() {
    const elapsed = Date.now() - this.stats.startTime;
    const filesPerSec = (this.stats.filesRead / elapsed) * 1000;
    const bytesPerSec = (this.stats.bytesRead / elapsed) * 1000;

    const termWidth = process.stdout.columns || 80;
    const maxPathLength = Math.max(40, termWidth - 60);

    // Clear previous lines and render new stats
    const output = [
      `${CLEAR_LINE}${MOVE_TO_START}`,
      `Files: ${this.formatNumber(this.stats.filesRead)} | `,
      `Dirs: ${this.formatNumber(this.stats.directoriesScanned)} | `,
      `Size: ${this.formatBytes(this.stats.bytesRead)} | `,
      `Speed: ${this.formatBytes(bytesPerSec)}/s | `,
      `Errors: ${this.stats.errors} | `,
      `Time: ${this.formatDuration(elapsed)}\n`,
      `${CLEAR_LINE}${MOVE_TO_START}`,
      `Current: ${this.truncatePath(this.stats.currentFile, maxPathLength)}`,
      `${MOVE_TO_START}`,
    ].join("");

    process.stdout.write(output);
  }

  getStats(): Stats {
    return { ...this.stats };
  }

  finalize() {
    this.render();
    process.stdout.write("\n\n");
    process.stdout.write(SHOW_CURSOR);

    const elapsed = Date.now() - this.stats.startTime;
    const avgSpeed = (this.stats.bytesRead / elapsed) * 1000;

    console.log("=== Final Statistics ===");
    console.log(
      `Total Files:       ${this.formatNumber(this.stats.filesRead)}`,
    );
    console.log(
      `Total Directories: ${this.formatNumber(this.stats.directoriesScanned)}`,
    );
    console.log(`Total Size:        ${this.formatBytes(this.stats.bytesRead)}`);
    console.log(`Errors:            ${this.stats.errors}`);
    console.log(`Duration:          ${this.formatDuration(elapsed)}`);
    console.log(`Average Speed:     ${this.formatBytes(avgSpeed)}/s`);
  }
}

async function processFile(
  filePath: string,
  display: ProgressDisplay,
): Promise<void> {
  try {
    display.updateStats({ currentFile: filePath });

    // Read the file to trigger OneDrive download
    const content = await readFile(filePath);

    // Get current stats using a method
    const currentStats = display.getStats();
    display.updateStats({
      filesRead: currentStats.filesRead + 1,
      bytesRead: currentStats.bytesRead + content.length,
    });
  } catch (error) {
    const currentStats = display.getStats();
    display.updateStats({
      errors: currentStats.errors + 1,
    });
  }
}

async function scanDirectory(
  dirPath: string,
  options: Options,
  display: ProgressDisplay,
  limit: ReturnType<typeof pLimit>,
  currentDepth = 0,
): Promise<void> {
  // Check depth limit
  if (options.maxDepth !== undefined && currentDepth >= options.maxDepth) {
    return;
  }

  try {
    const entries = await readdir(dirPath, { withFileTypes: true });

    const currentStats = display.getStats();
    display.updateStats({
      directoriesScanned: currentStats.directoriesScanned + 1,
    });

    // Separate files and directories
    const files: string[] = [];
    const directories: string[] = [];

    for (const entry of entries) {
      // Skip hidden files if requested
      if (options.skipHidden && entry.name.startsWith(".")) {
        continue;
      }

      const fullPath = join(dirPath, entry.name);

      if (entry.isDirectory()) {
        directories.push(fullPath);
      } else if (entry.isFile()) {
        files.push(fullPath);
      }
    }

    // Process all files in parallel (with concurrency limit)
    const filePromises = files.map((filePath) =>
      limit(() => processFile(filePath, display)),
    );

    // Process directories recursively (with concurrency limit)
    const dirPromises = directories.map((dirPath) =>
      limit(() =>
        scanDirectory(dirPath, options, display, limit, currentDepth + 1),
      ),
    );

    // Wait for all operations to complete
    await Promise.all([...filePromises, ...dirPromises]);
  } catch (error) {
    const currentStats = display.getStats();
    display.updateStats({
      errors: currentStats.errors + 1,
    });
  }
}

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .usage("Usage: $0 [path] [options]")
    .positional("path", {
      type: "string",
      description: "Directory path to scan",
      default: ".",
    })
    .option("path", {
      alias: "p",
      type: "string",
      description: "Directory path to scan",
    })
    .option("concurrency", {
      alias: "c",
      type: "number",
      description: "Number of concurrent file operations",
      default: 100,
    })
    .option("skip-hidden", {
      alias: "s",
      type: "boolean",
      description: "Skip hidden files and directories",
      default: false,
    })
    .option("max-depth", {
      alias: "d",
      type: "number",
      description: "Maximum directory depth to scan",
    })
    .help()
    .alias("help", "h")
    .example("$0 ~/Documents", "Scan Documents folder")
    .example("$0 -p ~/Documents", "Scan Documents folder (with flag)")
    .example(
      "$0 ~/OneDrive -c 200 -s",
      "Scan OneDrive with high concurrency, skip hidden files",
    )
    .example("$0 ~/Projects -d 3", "Scan Projects folder with max depth of 3")
    .argv;

  // Get path from positional argument or -p flag
  const targetPath = (argv._[0] as string) || argv.path || ".";

  const options: Options = {
    path: targetPath,
    concurrency: argv.concurrency,
    skipHidden: argv.skipHidden,
    maxDepth: argv.maxDepth,
  };

  // Verify path exists and is a directory
  try {
    const stats = await stat(options.path);
    if (!stats.isDirectory()) {
      console.error(`Error: ${options.path} is not a directory`);
      process.exit(1);
    }
  } catch (error) {
    console.error(`Error: Cannot access ${options.path}`);
    process.exit(1);
  }

  console.log(`Scanning: ${options.path}`);
  console.log(`Concurrency: ${options.concurrency}`);
  console.log(`Skip hidden: ${options.skipHidden}`);
  if (options.maxDepth !== undefined) {
    console.log(`Max depth: ${options.maxDepth}`);
  }
  console.log("");

  const display = new ProgressDisplay();
  const limit = pLimit(options.concurrency);

  try {
    await scanDirectory(options.path, options, display, limit);
    display.finalize();
  } catch (error) {
    display.finalize();
    console.error("\nFatal error:", error);
    process.exit(1);
  }
}

main();
