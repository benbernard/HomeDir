#!/usr/bin/env tsx

// Debug script to see what session info claude-notify would use

import { existsSync } from "fs";
import { homedir } from "os";
import { join } from "path";

const CLAUDE_PROJECTS_DIR = join(homedir(), ".claude", "projects");
const CACHE_DIR = join(homedir(), ".config", "claude-notify");
const CACHE_FILE = join(CACHE_DIR, "summaries.json");

function findGitRoot(cwd: string): string | null {
  let currentDir = cwd;
  const root = "/";

  while (currentDir !== root) {
    const gitPath = join(currentDir, ".git");
    if (existsSync(gitPath)) {
      return currentDir;
    }
    const parentDir = join(currentDir, "..");
    if (parentDir === currentDir) {
      break;
    }
    currentDir = parentDir;
  }

  return null;
}

function encodeProjectPath(path: string): string {
  return path.replace(/\//g, "-");
}

const sessionId =
  process.env.CLAUDE_SESSION_ID || process.ppid?.toString() || "default";
const cwd = process.cwd();
const gitRoot = findGitRoot(cwd) || cwd;
const encodedPath = encodeProjectPath(gitRoot);
const projectDir = join(CLAUDE_PROJECTS_DIR, encodedPath);
const sessionFile = join(projectDir, `${sessionId}.jsonl`);

console.log("=== claude-notify Debug Info ===");
console.log();
console.log("Environment:");
console.log(
  "  CLAUDE_SESSION_ID:",
  process.env.CLAUDE_SESSION_ID || "(not set)",
);
console.log("  process.ppid:", process.ppid);
console.log("  Derived sessionId:", sessionId);
console.log();
console.log("Paths:");
console.log("  cwd:", cwd);
console.log("  gitRoot:", gitRoot);
console.log("  encodedPath:", encodedPath);
console.log("  projectDir:", projectDir);
console.log("  sessionFile:", sessionFile);
console.log();
console.log("File checks:");
console.log("  Cache dir exists:", existsSync(CACHE_DIR));
console.log("  Cache file exists:", existsSync(CACHE_FILE));
console.log("  Project dir exists:", existsSync(projectDir));
console.log("  Session file exists:", existsSync(sessionFile));
console.log();

if (existsSync(sessionFile)) {
  console.log("✓ Session file found!");
} else {
  console.log("✗ Session file NOT found");
  console.log();
  console.log("Checking project directory...");
  if (existsSync(projectDir)) {
    const fs = require("fs");
    const files = fs.readdirSync(projectDir);
    console.log(`  Found ${files.length} files in project directory`);
    if (files.length > 0) {
      console.log("  Recent files:");
      for (const f of files.slice(0, 5)) {
        console.log(`    - ${f}`);
      }
    }
  } else {
    console.log("  Project directory doesn't exist!");
  }
}
