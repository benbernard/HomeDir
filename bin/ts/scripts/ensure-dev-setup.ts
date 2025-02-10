#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

console.log("Checking development environment setup...");

function runCommand(command: string, args: string[]) {
  console.log(`Running command: ${command} ${args.join(" ")}`);
  const result = spawnSync(command, args, { stdio: "inherit" });
  if (result.status !== 0) {
    console.error(`Command failed: ${command} ${args.join(" ")}`);
    process.exit(1);
  }
}

// Ensure dist directory exists and is up to date
runCommand("npm", ["run", "build"]);

// Check if package is globally installed
const isGloballyInstalled =
  spawnSync("npm", ["list", "-g", "bin-ben"]).status === 0;
if (!isGloballyInstalled) {
  console.log("Package not found globally, running link...");
  runCommand("npm", ["link"]);
}

// Check if package is properly linked
const nodeModulesPath = join(
  homedir(),
  ".nvm/versions/node",
  process.version,
  "lib/node_modules/bin-ben",
);

if (!existsSync(nodeModulesPath)) {
  console.log("Package link not found, re-linking...");
  runCommand("npm", ["link"]);
}

console.log("Development environment ready!");
