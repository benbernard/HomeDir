#!/usr/bin/env node

import { exec } from "child_process";
import { homedir } from "os";
import { join } from "path";
import { promisify } from "util";
import chalk from "chalk";
import clipboardy from "clipboardy";
import { JSDOM } from "jsdom";
import pLimit from "p-limit";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import { getHtmlFromClipboard } from "./clipboard";
import {
  DownloadItem,
  addDownloadItem,
  createTable,
  generateFilename,
  getById,
  listDownloadItems,
  removeById,
  removeByUrl,
  updateItemError,
} from "./db";
import { DownloadProgress, downloadFile } from "./download";

const execAsync = promisify(exec);

const DOWNLOADS_DIR = join(homedir(), "Downloads", "downloader");

interface LinkInfo {
  url: string;
  text: string;
}

function extractUrlsFromHtml(html: string): LinkInfo[] {
  const dom = new JSDOM(html);
  const document = dom.window.document;
  const links: LinkInfo[] = [];
  const anchors = document.querySelectorAll("a[href]");

  for (const anchor of Array.from(anchors) as HTMLAnchorElement[]) {
    const url = anchor.getAttribute("href");
    if (url) {
      links.push({
        url,
        text: anchor.textContent?.trim() || url,
      });
    }
  }

  return links;
}

async function getClipboardHtml(): Promise<string> {
  const html = getHtmlFromClipboard();
  if (html) {
    return html;
  }
  throw new Error("No HTML content found in clipboard");
}

function formatBytes(bytes: number): string {
  const units = ["B", "KB", "MB", "GB", "TB"];
  let size = bytes;
  let unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  return `${size.toFixed(1)}${units[unitIndex]}`;
}

function formatSpeed(bytesPerSecond: number): string {
  return `${formatBytes(bytesPerSecond)}/s`;
}

class DownloadManager {
  private activeDownloads = new Map<string, DownloadProgress>();
  private startTime = Date.now();
  private completedBytes = 0;
  private completedFiles = 0;
  private totalFiles = 0;
  private isLoopMode = false;
  private displayInterval: NodeJS.Timeout | null = null;

  constructor(
    private concurrency: number,
    private dryRun = false,
  ) {}

  setLoopMode(enabled: boolean) {
    this.isLoopMode = enabled;
  }

  setTotalFiles(count: number) {
    this.totalFiles = count;
  }

  updateProgress(progress: DownloadProgress) {
    this.activeDownloads.set(progress.id, progress);
    if (progress.status === "complete") {
      this.completedBytes += progress.bytesDownloaded;
      this.completedFiles++;
      this.activeDownloads.delete(progress.id);
    }
    this.displayProgress();
  }

  private displayProgress() {
    if (!this.displayInterval) {
      // Update display every 100ms
      this.displayInterval = setInterval(() => {
        this.renderProgress();
      }, 100);
    }
  }

  private renderProgress() {
    // Clear previous lines
    process.stdout.write("\x1B[2J\x1B[0f");

    // Calculate overall stats
    const elapsedSeconds = (Date.now() - this.startTime) / 1000;
    const currentBytes =
      this.completedBytes +
      Array.from(this.activeDownloads.values()).reduce(
        (sum, dl) => sum + dl.bytesDownloaded,
        0,
      );
    const overallSpeed = currentBytes / elapsedSeconds;

    // Display overall progress
    console.log(chalk.bold("Overall Progress:"));
    console.log(`Files: ${this.completedFiles}/${this.totalFiles}`);
    console.log(`Total downloaded: ${formatBytes(currentBytes)}`);
    console.log(`Average speed: ${formatSpeed(overallSpeed)}\n`);

    // Display active downloads
    console.log(chalk.bold("Active Downloads:"));
    for (const progress of this.activeDownloads.values()) {
      const status =
        progress.status === "downloading"
          ? chalk.yellow("⟳")
          : progress.status === "complete"
            ? chalk.green("✓")
            : chalk.red("✗");

      const speedInfo =
        progress.status === "downloading"
          ? `\n        Current Speed: ${formatSpeed(progress.recentSpeed)}`
          : "";

      console.log(
        `${status} ${progress.filename}
        ID: ${progress.id}
        URL: ${progress.url}
        Average Speed: ${formatSpeed(progress.averageSpeed)}${speedInfo}
        Progress: ${formatBytes(progress.bytesDownloaded)}`,
      );
    }
  }

  async downloadItems(items: DownloadItem[], targetDir: string): Promise<void> {
    const limit = pLimit(this.concurrency);
    const downloads = items.map((item) =>
      limit(() =>
        downloadFile(item, targetDir, (progress) =>
          this.updateProgress(progress),
        ).catch(async (error) => {
          if (error instanceof Error) {
            console.error(
              `\nError downloading ${item.filename}: ${error.message}`,
            );
            if (!this.dryRun) {
              await updateItemError(item.id, error.message);
            }
          }
        }),
      ),
    );

    await Promise.all(downloads);

    if (this.displayInterval) {
      clearInterval(this.displayInterval);
      this.displayInterval = null;
    }
  }
}

yargs(hideBin(process.argv))
  .command(
    "migrate",
    "Create the DynamoDB table",
    (yargs) => {
      return yargs;
    },
    async () => {
      await createTable();
    },
  )
  .command(
    "remove",
    "Remove an item by ID or URL",
    (yargs) => {
      return yargs
        .option("id", {
          alias: "i",
          type: "string",
          description: "ID of the item to remove",
          conflicts: "url",
        })
        .option("url", {
          alias: "u",
          type: "string",
          description: "URL of the item to remove",
          conflicts: "id",
        })
        .check((argv) => {
          if (!argv.id && !argv.url) {
            throw new Error("Either --id or --url must be specified");
          }
          return true;
        });
    },
    async (argv) => {
      try {
        if (argv.id) {
          await removeById(argv.id);
          console.log(`Successfully removed item with ID: ${argv.id}`);
        } else if (argv.url) {
          await removeByUrl(argv.url);
          console.log(`Successfully removed item with URL: ${argv.url}`);
        }
      } catch (error) {
        if (error instanceof Error) {
          console.error(`Error: ${error.message}`);
          process.exit(1);
        }
        throw error;
      }
    },
  )
  .command(
    "list",
    "List available items",
    (yargs) => {
      return yargs.option("errors", {
        alias: "e",
        type: "boolean",
        description: "Show only items with errors",
        default: false,
      });
    },
    async (argv) => {
      const items = await listDownloadItems(argv.errors);
      if (items.length === 0) {
        console.log(argv.errors ? "No items with errors" : "No items in queue");
        return;
      }

      if (argv.errors) {
        console.log(`Failed Downloads (${items.length} items):`);
      } else {
        const errorCount = items.filter((item) => item.error).length;
        const downloadableCount = items.length - errorCount;
        console.log(
          `Download Queue Items (${items.length} total: ${downloadableCount} pending, ${errorCount} failed):`,
        );
      }

      for (const item of items) {
        console.log(
          `- ${item.id}: ${item.filename} (${item.url})${
            item.error ? `\n  Error: ${item.error}` : ""
          }${item.lastAttempt ? `\n  Last attempt: ${item.lastAttempt}` : ""}`,
        );
      }
    },
  )
  .command(
    "download",
    "Download an item",
    (yargs) => {
      return yargs
        .option("id", {
          alias: "i",
          type: "string",
          description: "ID of the item to download",
          conflicts: "loop",
        })
        .option("dir", {
          alias: "d",
          type: "string",
          description: "Target directory for downloads",
          default: DOWNLOADS_DIR,
        })
        .option("loop", {
          alias: "l",
          type: "boolean",
          description: "Continuously process download queue",
          conflicts: "id",
        })
        .option("jobs", {
          alias: "j",
          type: "number",
          description: "Number of parallel downloads",
          default: 1,
        })
        .option("dry-run", {
          type: "boolean",
          description: "Download files but don't remove from queue",
          default: false,
        })
        .check((argv) => {
          if (!argv.id && !argv.loop) {
            throw new Error("Either --id or --loop must be specified");
          }
          if (argv.jobs < 1) {
            throw new Error("Number of jobs must be at least 1");
          }
          return true;
        });
    },
    async (argv) => {
      const downloadManager = new DownloadManager(argv.jobs, argv.dryRun);

      if (argv.loop) {
        console.log(
          `Starting continuous download processing with ${
            argv.jobs
          } parallel downloads${
            argv.dryRun ? " (dry run)" : ""
          }. Press Ctrl+C to stop.`,
        );

        let totalProcessed = 0;
        const knownItems = new Set<string>();

        while (true) {
          const items = await listDownloadItems();
          const downloadableItems = items.filter((item) => !item.error);
          const errorItems = items.filter((item) => item.error);

          // Show error items if any
          if (errorItems.length > 0) {
            console.log("\nItems with errors:");
            for (const item of errorItems) {
              console.log(`${item.filename}: ${item.error}`);
            }
          }

          // Check for new items and update total
          for (const item of downloadableItems) {
            if (!knownItems.has(item.id)) {
              knownItems.add(item.id);
              totalProcessed++;
              downloadManager.setTotalFiles(totalProcessed);
            }
          }

          if (downloadableItems.length === 0) {
            console.log("\nNo items available to download. Waiting...");
            await new Promise((resolve) => setTimeout(resolve, 5000));
            continue;
          }

          // Download items in parallel
          await downloadManager.downloadItems(downloadableItems, argv.dir);

          // Remove completed items if not in dry run mode
          if (!argv.dryRun) {
            for (const item of downloadableItems) {
              try {
                await removeById(item.id);
              } catch (error) {
                // Ignore errors here as they'll be caught in the next iteration
              }
            }
          }
        }
      } else {
        if (!argv.id) {
          console.error("ID is required when not in loop mode");
          process.exit(1);
        }

        const item = await getById(argv.id);

        if (!item) {
          console.error(`No item found with id: ${argv.id}`);
          process.exit(1);
        }

        if (item.error) {
          console.error(
            `This item previously failed with error: ${item.error}\nUse remove and add again to retry.`,
          );
          process.exit(1);
        }

        try {
          downloadManager.setTotalFiles(1); // Set total to 1 for single-item mode
          await downloadManager.downloadItems([item], argv.dir);
          if (!argv.dryRun) {
            await removeById(item.id);
          }
          console.log(
            `\nDownload complete: ${argv.dir}/${item.filename}${
              argv.dryRun ? " (dry run - item not removed from queue)" : ""
            }`,
          );
        } catch (error) {
          if (error instanceof Error) {
            console.error(`\nError: ${error.message}`);
            process.exit(1);
          }
          throw error;
        }
      }
    },
  )
  .command(
    "add",
    "Add a new item",
    (yargs) => {
      return yargs
        .option("url", {
          alias: "u",
          type: "string",
          description: "URL of the item to download",
          demandOption: true,
        })
        .option("name", {
          alias: "n",
          type: "string",
          description: "Name for the download (optional)",
        });
    },
    async (argv) => {
      const item = await addDownloadItem(argv.url, argv.name || argv.url);
      console.log(
        `Added download item: ${item.id}: ${item.filename} (${item.url})`,
      );
    },
  )
  .command(
    "fromclipboard",
    "Add download items from HTML in clipboard",
    (yargs) => {
      return yargs
        .option("dry-run", {
          alias: "d",
          type: "boolean",
          description: "Preview URLs without adding them to the queue",
          default: false,
        })
        .option("verbose", {
          alias: "v",
          type: "boolean",
          description: "Show raw clipboard content",
          default: false,
        })
        .option("confirm", {
          alias: "c",
          type: "boolean",
          description: "Confirm before adding items",
          default: false,
        })
        .option("loop", {
          alias: "l",
          type: "boolean",
          description:
            "Continuously process clipboard content (press Enter to process, Ctrl+C to exit)",
          default: false,
        });
    },
    async (argv) => {
      async function processClipboard() {
        try {
          const clipboardContent = await getClipboardHtml();

          if (argv.verbose) {
            console.log("Raw clipboard content:");
            console.log("----------------------------------------");
            console.log(clipboardContent);
            console.log("----------------------------------------\n");
          }

          const links = extractUrlsFromHtml(clipboardContent);

          if (links.length === 0) {
            console.log("No URLs found in clipboard HTML content");
            return;
          }

          console.log(`Found ${links.length} URLs in clipboard:`);
          for (const link of links) {
            const filename = generateFilename(link.text);
            console.log(`${filename} (${link.url})`);
          }

          if (argv.dryRun) {
            console.log(
              "\nThis was a dry run. No URLs were added to the queue.",
            );
            return;
          }

          if (argv.confirm) {
            process.stdout.write(
              "\nPress Enter to add these items to the queue (Ctrl+C to cancel)...",
            );
            await new Promise((resolve) => {
              const cleanup = () => {
                process.stdin.removeAllListeners("data");
                process.stdin.pause();
              };

              process.stdin.resume();
              process.stdin.once("data", () => {
                cleanup();
                resolve(undefined);
              });
            });
          }

          for (const link of links) {
            const item = await addDownloadItem(link.url, link.text);
            console.log(`Added: ${item.id}: ${item.filename} (${item.url})`);
          }
        } catch (error) {
          if (error instanceof Error) {
            console.error(`Error: ${error.message}`);
            if (!argv.loop) process.exit(1);
          }
          throw error;
        }
      }

      if (argv.loop) {
        console.log(
          "Starting clipboard processing loop. Press Ctrl+C to exit.",
        );
        while (true) {
          process.stdout.write("\nPress Enter to process clipboard content...");
          await new Promise((resolve) => {
            const cleanup = () => {
              process.stdin.removeAllListeners("data");
              process.stdin.pause();
            };

            process.stdin.resume();
            process.stdin.once("data", () => {
              cleanup();
              resolve(undefined);
            });
          });
          console.log("\n"); // Add a blank line for readability
          await processClipboard();
        }
      } else {
        await processClipboard();
      }
    },
  )
  .demandCommand(1, "You must specify a command")
  .strict()
  .help().argv;
