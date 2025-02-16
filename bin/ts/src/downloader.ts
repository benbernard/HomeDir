#!/usr/bin/env node

import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import { promisify } from "util";
import { exec } from "child_process";
import clipboardy from "clipboardy";
import { getHtmlFromClipboard } from "./clipboard";
import {
  createTable,
  addDownloadItem,
  listDownloadItems,
  removeById,
  removeByUrl,
  generateFilename,
  updateItemError,
  getById,
} from "./db";
import { JSDOM } from "jsdom";
import { downloadFile } from "./download";
import { homedir } from "os";
import { join } from "path";

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

      console.log(argv.errors ? "Failed Downloads:" : "Download Queue Items:");
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
        .check((argv) => {
          if (!argv.id && !argv.loop) {
            throw new Error("Either --id or --loop must be specified");
          }
          return true;
        });
    },
    async (argv) => {
      if (argv.loop) {
        console.log(
          "Starting continuous download processing. Press Ctrl+C to stop.",
        );

        let totalProcessed = 0;
        const knownItems = new Set<string>(); // Track items we've seen by ID

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
            }
          }

          // Get the first non-error item
          const item = downloadableItems[0];

          if (!item) {
            // No items to download
            console.log("\nNo items available to download. Waiting...");
            await new Promise((resolve) => setTimeout(resolve, 5000));
            continue;
          }

          const remaining = downloadableItems.length;
          console.log(
            `\nDownloading ${
              totalProcessed - remaining + 1
            }/${totalProcessed}: ${item.filename} from ${item.url}`,
          );

          try {
            await downloadFile(item, argv.dir);
            console.log(`Download complete: ${argv.dir}/${item.filename}`);
            await removeById(item.id);
            console.log("Item removed from queue");
          } catch (error) {
            if (error instanceof Error) {
              console.error(`Error: ${error.message}`);
              await updateItemError(item.id, error.message);
            }
          }
        }
      } else {
        // Original single-item download logic
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

        console.log(`Downloading ${item.filename} from ${item.url}`);

        try {
          await downloadFile(item, argv.dir);
          console.log(`\nDownload complete: ${argv.dir}/${item.filename}`);
          await removeById(item.id);
          console.log("Item removed from queue");
        } catch (error) {
          if (error instanceof Error) {
            console.error(`\nError: ${error.message}`);
            await updateItemError(argv.id, error.message);
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
        });
    },
    async (argv) => {
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
          console.log("\nThis was a dry run. No URLs were added to the queue.");
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
          process.exit(1);
        }
        throw error;
      }
    },
  )
  .demandCommand(1, "You must specify a command")
  .strict()
  .help().argv;
