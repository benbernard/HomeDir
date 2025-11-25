import { execSync, spawnSync } from "child_process";

export function execGit(args: string[], silent = false): string {
  try {
    return execSync(`git ${args.join(" ")}`, {
      encoding: "utf-8",
      stdio: silent ? "pipe" : ["pipe", "pipe", "pipe"],
    }).trim();
  } catch (error) {
    if (!silent) throw error;
    return "";
  }
}

export function execGitSafe(args: string[]): {
  stdout: string;
  stderr: string;
  status: number;
} {
  const result = spawnSync("git", args, {
    encoding: "utf-8",
  });
  return {
    stdout: (result.stdout || "").trim(),
    stderr: (result.stderr || "").trim(),
    status: result.status || 0,
  };
}
