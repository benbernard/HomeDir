#!/usr/bin/env bun

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
runCommand("bun", ["run", "build"]);

// Check if package is globally installed
const isGloballyInstalled = spawnSync("bun", ["pm", "ls", "-g"])
  .stdout?.toString()
  .includes("bin-ben");
if (!isGloballyInstalled) {
  console.log("Package not found globally, running link...");
  runCommand("bun", ["link"]);
}

console.log("Development environment ready!");
