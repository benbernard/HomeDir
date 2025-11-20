#!/usr/bin/env tsx

import { join } from "path";
import { readFile, readdir, stat } from "fs/promises";
import pLimit from "p-limit";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

interface Stats {
  filesRead: number;
  filesReading: number;
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
  private readonly UPDATE_INTERVAL_MS = 200; // Update every 200ms
  private isShuttingDown = false;
  private isFirstRender = true;

  constructor() {
    this.stats = {
      filesRead: 0,
      filesReading: 0,
      directoriesScanned: 0,
      bytesRead: 0,
      errors: 0,
      startTime: Date.now(),
      currentFile: "",
    };

    // Hide cursor for cleaner output
    process.stdout.write(HIDE_CURSOR);

    // Start periodic rendering
    this.updateInterval = setInterval(() => {
      this.render();
    }, this.UPDATE_INTERVAL_MS);

    // Ensure cursor is shown on exit
    process.on("exit", () => {
      if (this.updateInterval) {
        clearInterval(this.updateInterval);
      }
      if (!this.isShuttingDown) {
        process.stdout.write(`${SHOW_CURSOR}\n`);
      }
    });
    process.on("SIGINT", () => {
      this.isShuttingDown = true;
      if (this.updateInterval) {
        clearInterval(this.updateInterval);
      }
      process.stdout.write(`${SHOW_CURSOR}\n`);
      console.log("\nInterrupted by user");
      process.exit(130); // Standard exit code for Ctrl+C
    });
    process.on("SIGTERM", () => {
      this.isShuttingDown = true;
      if (this.updateInterval) {
        clearInterval(this.updateInterval);
      }
      process.stdout.write(`${SHOW_CURSOR}\n`);
      process.exit(143);
    });
  }

  updateStats(update: Partial<Stats>) {
    Object.assign(this.stats, update);
    // Stats will be rendered by the interval timer
  }

  // Atomic increment/decrement operations to avoid race conditions
  incrementFilesReading() {
    this.stats.filesReading++;
  }

  decrementFilesReading() {
    this.stats.filesReading--;
  }

  incrementFilesRead() {
    this.stats.filesRead++;
  }

  addBytesRead(bytes: number) {
    this.stats.bytesRead += bytes;
  }

  incrementErrors() {
    this.stats.errors++;
  }

  setCurrentFile(filePath: string) {
    this.stats.currentFile = filePath;
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
    // Simple number formatting without toLocaleString for better performance
    return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
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

    // Build the output
    const statsLine = [
      `Files: ${this.formatNumber(this.stats.filesRead)} | `,
      `Reading: ${this.stats.filesReading} | `,
      `Dirs: ${this.formatNumber(this.stats.directoriesScanned)} | `,
      `Size: ${this.formatBytes(this.stats.bytesRead)} | `,
      `Speed: ${this.formatBytes(bytesPerSec)}/s | `,
      `Errors: ${this.stats.errors} | `,
      `Time: ${this.formatDuration(elapsed)}`,
    ].join("");

    const currentLine = `Current: ${this.truncatePath(
      this.stats.currentFile,
      maxPathLength,
    )}`;

    let output: string;
    if (this.isFirstRender) {
      // First render: just write the lines
      output = `${statsLine}\n${currentLine}`;
      this.isFirstRender = false;
    } else {
      // Subsequent renders: move to start of current line, move up 1 line, clear both lines and redraw
      output = `${MOVE_TO_START}\x1b[1A${CLEAR_LINE}${statsLine}\n${CLEAR_LINE}${currentLine}`;
    }

    process.stdout.write(output);
  }

  getStats(): Stats {
    return { ...this.stats };
  }

  finalize() {
    // Stop the update interval
    if (this.updateInterval) {
      clearInterval(this.updateInterval);
    }

    // Do one final render
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
    // Increment reading count atomically
    display.incrementFilesReading();
    display.setCurrentFile(filePath);

    // Read the file to trigger OneDrive download
    const content = await readFile(filePath);

    // Update stats after successful read
    display.incrementFilesRead();
    display.decrementFilesReading();
    display.addBytesRead(content.length);
  } catch (error) {
    display.incrementErrors();
    display.decrementFilesReading();
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
      } else if (entry.isSymbolicLink()) {
        // Handle symlinks by checking what they point to
        try {
          const stats = await stat(fullPath);
          if (stats.isDirectory()) {
            directories.push(fullPath);
          } else if (stats.isFile()) {
            files.push(fullPath);
          }
        } catch {
          // Skip broken symlinks
        }
      }
    }

    // Queue all file operations through the limiter
    const filePromises = files.map((filePath) =>
      limit(() => processFile(filePath, display)),
    );

    // Recursively scan subdirectories (don't limit directory scanning, only file reading)
    const dirPromises = directories.map((dirPath) =>
      scanDirectory(dirPath, options, display, limit, currentDepth + 1),
    );

    // Wait for all operations in this directory to complete
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
      default: 20,
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
      "$0 ~/OneDrive -c 50 -s",
      "Scan OneDrive with higher concurrency, skip hidden files",
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
