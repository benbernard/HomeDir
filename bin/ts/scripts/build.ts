#!/usr/bin/env bun

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
import { excludedFiles, scripts } from "../src/manifest";

const rootDir = join(import.meta.dirname, "..");
const srcDir = join(rootDir, "src");
const distDir = join(rootDir, "dist");
const binDir = join(rootDir, "bin");
const gitignorePath = join(rootDir, ".gitignore");

const isWatch = process.argv.includes("--watch");
const singleFileIndex = process.argv.indexOf("--single");
const singleFile =
  singleFileIndex !== -1 ? process.argv[singleFileIndex + 1] : null;

/**
 * Get entry points from manifest (only files that should be executable)
 */
function getEntryPoints(): string[] {
  const manifestFiles = new Set(Object.values(scripts).map((s) => s.file));
  return Array.from(manifestFiles).map((file) => join(srcDir, file));
}

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
 * Rename compiled binaries to command names and make executable in dist/
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
    // Bun --compile creates files without extension or with the source name
    // Check if this file corresponds to a manifest entry
    const baseName = file.replace(/\.js$/, ""); // In case there are any .js files
    const commandName = manifestFileToName.get(baseName);

    if (commandName && commandName !== file) {
      const oldPath = join(distDir, file);
      const newPath = join(distDir, commandName);

      // Remove existing file if it exists
      if (existsSync(newPath) && newPath !== oldPath) {
        unlinkSync(newPath);
      }

      renameSync(oldPath, newPath);
      chmodSync(newPath, 0o755);
      processedNames.add(commandName);
    } else if (existsSync(join(distDir, file))) {
      // Make sure file is executable
      chmodSync(join(distDir, file), 0o755);
    }
  }
}

/**
 * Build a single entry point using Bun CLI with --compile
 */
async function buildEntry(entryPoint: string): Promise<void> {
  const fileName = entryPoint.split("/").pop()?.replace(/\.ts$/, "") ?? "";
  const outfile = join(distDir, fileName);

  // Use Bun CLI directly since the API doesn't respect outfile with compile
  const proc = Bun.spawn(
    [
      "bun",
      "build",
      entryPoint,
      "--compile",
      "--outfile",
      outfile,
      "--target",
      "bun-darwin-arm64",
    ],
    {
      cwd: rootDir,
      stdout: "pipe",
      stderr: "pipe",
    },
  );

  const exitCode = await proc.exited;

  if (exitCode !== 0) {
    const stderr = await new Response(proc.stderr).text();
    console.error(`Failed to build ${fileName}:`);
    console.error(stderr);
    throw new Error(`Build failed for ${fileName}`);
  }

  // Make executable
  chmodSync(outfile, 0o755);
}

/**
 * Generate wrapper scripts that check timestamps and rebuild if needed
 */
function generateWrappers(): void {
  // Ensure bin directory exists
  if (!existsSync(binDir)) {
    console.log("Creating bin/ directory...");
    const { mkdirSync } = require("fs");
    mkdirSync(binDir, { recursive: true });
  }

  // Clean up old wrappers that aren't in the manifest
  if (existsSync(binDir)) {
    const validNames = new Set(Object.keys(scripts));
    const files = readdirSync(binDir);
    for (const file of files) {
      const filePath = join(binDir, file);
      try {
        const stat = lstatSync(filePath);
        // Remove files that aren't directories and aren't in manifest
        if (stat.isFile() && !validNames.has(file)) {
          console.log(`Removing stale wrapper: ${file}`);
          unlinkSync(filePath);
        }
      } catch {
        // Ignore errors
      }
    }
  }

  console.log("Generating wrapper scripts in bin/...");

  for (const [name, entry] of Object.entries(scripts)) {
    const wrapperPath = join(binDir, name);
    const sourceFile = entry.file;
    const sourcePath = join(srcDir, sourceFile);
    const binaryPath = join(distDir, name);

    const wrapperContent = `#!/usr/bin/env bash
# Auto-generated wrapper for ${name}
# Checks if source is newer than binary and rebuilds if needed

SOURCE="${sourcePath}"
BINARY="${binaryPath}"
BUILD_SCRIPT="${join(rootDir, "scripts/build.ts")}"

# Check if source is newer than binary
if [[ "$SOURCE" -nt "$BINARY" ]]; then
  echo "Source changed, rebuilding ${name}..." >&2
  cd "${rootDir}" && bun run "\${BUILD_SCRIPT}" --single "${sourceFile}" >/dev/null 2>&1 || {
    echo "Build failed for ${name}" >&2
    exit 1
  }
fi

# Execute the binary
exec "\${BINARY}" "$@"
`;

    writeFileSync(wrapperPath, wrapperContent);
    chmodSync(wrapperPath, 0o755);
  }
}

/**
 * Build all entry points
 */
async function buildAll(): Promise<void> {
  const entryPoints = getEntryPoints();
  console.log(`Building ${entryPoints.length} scripts...`);

  // Ensure dist directory exists
  if (!existsSync(distDir)) {
    const { mkdirSync } = require("fs");
    mkdirSync(distDir, { recursive: true });
  }

  // Build in parallel for speed
  await Promise.all(entryPoints.map((entry) => buildEntry(entry)));

  processDistFiles();
  generateWrappers();
}

async function main(): Promise<void> {
  // Handle single file build
  if (singleFile) {
    const entryPoint = join(srcDir, singleFile);
    if (!existsSync(entryPoint)) {
      console.error(`File not found: ${entryPoint}`);
      process.exit(1);
    }
    await buildEntry(entryPoint);
    processDistFiles();
    return;
  }

  // Warn about unlisted files at the start
  warnAboutUnlistedFiles();

  // Create src symlinks
  console.log("Creating src/ symlinks from manifest...");
  createSrcSymlinks();

  // Update .gitignore with symlink entries
  updateGitignore();

  if (isWatch) {
    // Do initial build
    await buildAll();
    console.log("Initial build complete. Watching for changes...");

    // Watch for changes and rebuild
    const chokidar = await import("chokidar");

    // Get list of files to watch from manifest
    const entryPoints = getEntryPoints();
    const watchPaths = [...entryPoints, join(srcDir, "manifest.ts")];

    const watcher = chokidar.default.watch(watchPaths, { ignoreInitial: true });

    let rebuildTimer: Timer | null = null;

    watcher.on("change", async (path) => {
      if (path.endsWith("manifest.ts")) {
        console.log("Manifest changed, regenerating symlinks...");
        console.log(
          "Note: Manifest changes require restarting build:watch to take effect.",
        );
        return;
      }

      // Debounce rebuilds
      if (rebuildTimer) {
        clearTimeout(rebuildTimer);
      }

      rebuildTimer = setTimeout(async () => {
        try {
          const fileName = path.split("/").pop() || "";
          console.log(`Rebuilding ${fileName}...`);
          await buildEntry(path);
          processDistFiles();
          console.log("Rebuild complete");
        } catch (err) {
          console.error("Rebuild failed:", err);
        }
      }, 100);
    });

    // Keep process alive
    process.stdin.resume();
  } else {
    await buildAll();
    warnAboutUnlistedFiles();
    console.log("Build complete");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
