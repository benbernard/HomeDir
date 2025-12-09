#!/usr/bin/env tsx

import {
  chmodSync,
  existsSync,
  lstatSync,
  readFileSync,
  readdirSync,
  readlinkSync,
  renameSync,
  symlinkSync,
  unlinkSync,
  writeFileSync,
} from "fs";
import { join } from "path";
import { type BuildOptions, build, context } from "esbuild";
import { excludedFiles, scripts } from "../src/manifest";

const rootDir = join(import.meta.dirname, "..");
const srcDir = join(rootDir, "src");
const distDir = join(rootDir, "dist");
const gitignorePath = join(rootDir, ".gitignore");

// Get all .ts files in src directory
const entryPoints = readdirSync(srcDir)
  .filter((file) => file.endsWith(".ts"))
  .map((file) => join(srcDir, file));

const isWatch = process.argv.includes("--watch");

const buildOptions: BuildOptions = {
  entryPoints,
  bundle: false,
  platform: "node",
  target: "node18",
  outdir: distDir,
  format: "cjs",
};

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

/**
 * Warn about files not in the manifest
 */
function warnAboutUnlistedFiles(): void {
  const unlisted = getUnlistedFiles();
  if (unlisted.length > 0) {
    console.warn(
      "\n⚠️  Warning: The following .ts files are not in the manifest:",
    );
    for (const file of unlisted) {
      console.warn(`   - ${file}`);
    }
    console.warn(
      "   Add them to manifest.ts or excludedFiles if they should not be executable.\n",
    );
  }
}

/**
 * Clean up symlinks in a directory that are not in the manifest
 */
function cleanupStaleSymlinks(dir: string, validNames: Set<string>): void {
  if (!existsSync(dir)) return;

  const files = readdirSync(dir);
  for (const file of files) {
    const filePath = join(dir, file);
    try {
      const stat = lstatSync(filePath);
      // In src/, check for symlinks; in dist/, check for executable files without extension
      if (dir === srcDir && stat.isSymbolicLink()) {
        if (!validNames.has(file)) {
          console.log(`Removing stale symlink: ${file}`);
          unlinkSync(filePath);
        }
      }
    } catch {
      // Ignore errors
    }
  }
}

const GITIGNORE_START_MARKER =
  "# Auto-generated symlinks (do not edit this section)";
const GITIGNORE_END_MARKER = "# End auto-generated symlinks";

/**
 * Update .gitignore with symlink entries from manifest
 */
function updateGitignore(): void {
  const symlinkEntries = Object.keys(scripts)
    .sort()
    .map((name) => `src/${name}`);

  let content = "";
  if (existsSync(gitignorePath)) {
    content = readFileSync(gitignorePath, "utf-8");
  }

  // Check if we have an existing auto-generated section
  const startIdx = content.indexOf(GITIGNORE_START_MARKER);
  const endIdx = content.indexOf(GITIGNORE_END_MARKER);

  const newSection = [
    GITIGNORE_START_MARKER,
    ...symlinkEntries,
    GITIGNORE_END_MARKER,
  ].join("\n");

  let newContent: string;
  if (startIdx !== -1 && endIdx !== -1) {
    // Replace existing section
    newContent =
      content.slice(0, startIdx) +
      newSection +
      content.slice(endIdx + GITIGNORE_END_MARKER.length);
  } else {
    // Add new section at the end
    newContent = `${content.trimEnd()}\n\n${newSection}\n`;
  }

  // Only write if changed
  if (newContent !== content) {
    writeFileSync(gitignorePath, newContent);
    console.log("Updated .gitignore with symlink entries");
  }
}

/**
 * Create symlinks in src/ directory: name -> name.ts
 */
function createSrcSymlinks(): void {
  const validNames = new Set(Object.keys(scripts));

  // Clean up stale symlinks first
  cleanupStaleSymlinks(srcDir, validNames);

  for (const [name, entry] of Object.entries(scripts)) {
    const symlinkPath = join(srcDir, name);
    const targetFile = entry.file;

    try {
      // Check if symlink already exists and points to correct target
      if (existsSync(symlinkPath)) {
        const stat = lstatSync(symlinkPath);
        if (stat.isSymbolicLink()) {
          const currentTarget = readlinkSync(symlinkPath);
          if (currentTarget === targetFile) {
            continue; // Already correct
          }
        }
        // Remove existing file/symlink
        unlinkSync(symlinkPath);
      }

      // Create new symlink
      symlinkSync(targetFile, symlinkPath);
    } catch (err) {
      console.error(`Error creating symlink ${name} -> ${targetFile}:`, err);
    }
  }
}

/**
 * Rename .js files to command names and make executable in dist/
 * Only processes files that are in the manifest
 */
function processDistFiles(): void {
  if (!existsSync(distDir)) return;

  const files = readdirSync(distDir);
  const manifestFileToName = new Map<string, string>();

  // Build reverse map: source file (without .ts) -> command name
  for (const [name, entry] of Object.entries(scripts)) {
    const baseName = entry.file.replace(/\.ts$/, "");
    manifestFileToName.set(baseName, name);
  }

  // Track which command names we've processed
  const processedNames = new Set<string>();

  for (const file of files) {
    if (file.endsWith(".js")) {
      const baseName = file.replace(/\.js$/, "");
      const commandName = manifestFileToName.get(baseName);

      if (commandName) {
        const oldPath = join(distDir, file);
        const newPath = join(distDir, commandName);

        // Remove existing file if it exists
        if (existsSync(newPath) && newPath !== oldPath) {
          unlinkSync(newPath);
        }

        renameSync(oldPath, newPath);
        chmodSync(newPath, 0o755);
        processedNames.add(commandName);
      } else {
        // Not in manifest - remove the .js extension anyway for consistency
        // but don't create a command symlink
        const oldPath = join(distDir, file);
        const newPath = join(distDir, baseName);
        if (existsSync(newPath) && newPath !== oldPath) {
          unlinkSync(newPath);
        }
        renameSync(oldPath, newPath);
        chmodSync(newPath, 0o755);
      }
    }
  }
}

async function main(): Promise<void> {
  // Warn about unlisted files at the start
  warnAboutUnlistedFiles();

  // Create src symlinks
  console.log("Creating src/ symlinks from manifest...");
  createSrcSymlinks();

  // Update .gitignore with symlink entries
  updateGitignore();

  if (isWatch) {
    const ctx = await context(buildOptions);

    // Do initial build
    await ctx.rebuild();
    processDistFiles();
    console.log("Initial build complete. Watching for changes...");

    // Start watching
    await ctx.watch();

    // Watch for changes and process
    const chokidar = await import("chokidar");

    // Watch both dist/*.js and manifest.ts for changes
    const watcher = chokidar.default.watch(
      [join(distDir, "*.js"), join(import.meta.dirname, "../manifest.ts")],
      { ignoreInitial: true },
    );

    watcher.on("add", (path) => {
      if (path.endsWith(".js")) {
        setTimeout(() => {
          try {
            processDistFiles();
            console.log("Rebuild complete");
          } catch {
            // Ignore errors during processing
          }
        }, 100);
      }
    });

    watcher.on("change", (path) => {
      if (path.endsWith("manifest.ts")) {
        console.log("Manifest changed, regenerating symlinks...");
        // Note: In watch mode, manifest changes require restart to take effect
        // because the module is already cached. This is a limitation.
        console.log(
          "Note: Manifest changes require restarting build:watch to take effect.",
        );
      }
    });
  } else {
    await build(buildOptions);
    processDistFiles();
    warnAboutUnlistedFiles();
    console.log("Build complete");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
