#!/usr/bin/env tsx

import { readdirSync } from "fs";
import { dirname } from "path";
import { fileURLToPath } from "url";
import chalk from "chalk";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import { excludedFiles, scripts } from "./manifest";

// This file is in src/, so __dirname equivalent is the src directory
const srcDir = dirname(fileURLToPath(import.meta.url));

/**
 * Get all .ts files in src that are not in the manifest and not excluded
 */
function getUnlistedFiles(): string[] {
  const allTsFiles = readdirSync(srcDir).filter(
    (file) => file.endsWith(".ts") && !file.endsWith(".test.ts"),
  );

  const manifestFiles = new Set(Object.values(scripts).map((s) => s.file));
  const excludedSet = new Set(excludedFiles);

  return allTsFiles.filter(
    (file) => !manifestFiles.has(file) && !excludedSet.has(file),
  );
}

async function main(): Promise<void> {
  const argv = await yargs(hideBin(process.argv))
    .scriptName("ben-scripts")
    .usage("$0 [options]")
    .option("json", {
      alias: "j",
      type: "boolean",
      description: "Output as JSON",
      default: false,
    })
    .option("warn", {
      alias: "w",
      type: "boolean",
      description: "Show warnings about unlisted files",
      default: true,
    })
    .help()
    .alias("help", "h")
    .example("$0", "List all scripts")
    .example("$0 --json", "Output as JSON")
    .example("$0 --no-warn", "Suppress warnings").argv;

  const entries = Object.entries(scripts).sort(([a], [b]) =>
    a.localeCompare(b),
  );

  if (argv.json) {
    const output = entries.map(([name, entry]) => ({
      name,
      file: entry.file,
      description: entry.description,
    }));
    console.log(JSON.stringify(output, null, 2));
    return;
  }

  // Calculate column widths
  const maxNameLen = Math.max(...entries.map(([name]) => name.length));

  console.log(chalk.bold("\nAvailable scripts:\n"));

  for (const [name, entry] of entries) {
    const paddedName = name.padEnd(maxNameLen);
    console.log(`  ${chalk.cyan(paddedName)}  ${entry.description}`);
  }

  console.log();

  // Check for unlisted files
  if (argv.warn) {
    const unlisted = getUnlistedFiles();
    if (unlisted.length > 0) {
      console.log(
        chalk.yellow(
          "Warning: The following .ts files are not in the manifest:",
        ),
      );
      for (const file of unlisted) {
        console.log(chalk.yellow(`  - ${file}`));
      }
      console.log(
        chalk.gray(
          "\nAdd them to manifest.ts or excludedFiles if they should not be listed.\n",
        ),
      );
    }
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
