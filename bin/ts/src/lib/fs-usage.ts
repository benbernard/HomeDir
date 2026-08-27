import { basename, dirname } from "node:path";

export type FsActivityKind = "metadata" | "read" | "write" | "other";

const METADATA_CALLS = new Set([
  "access",
  "fstat64",
  "fstatat64",
  "fsgetpath",
  "getattrlist",
  "getattrlistbulk",
  "lstat64",
  "readlink",
  "stat64",
]);

const READ_CALLS = new Set(["readdata", "rddata", "read", "readv", "pread"]);

const WRITE_CALLS = new Set([
  "chmod",
  "chown",
  "fchmod",
  "fchown",
  "fsetxattr",
  "fsync",
  "ftruncate",
  "mkdir",
  "pwrite",
  "removexattr",
  "rename",
  "renameat",
  "rmdir",
  "setattrlist",
  "setxattr",
  "truncate",
  "unlink",
  "unlinkat",
  "write",
  "writedata",
  "writev",
  "wrdata",
]);

function escapeRegex(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function lineMentionsExactPath(line: string, path: string): boolean {
  return new RegExp(`${escapeRegex(path)}(?=\\s|$)`).test(line);
}

export function lineMentionsTargetFamily(
  line: string,
  target: string,
): boolean {
  const directory = escapeRegex(dirname(target));
  const name = escapeRegex(basename(target));
  return new RegExp(
    `${directory}/(?:\\.)?${name}(?:\\.[^\\s/]*)?(?=\\s|$)`,
  ).test(line);
}

export function lineMentionsPathWithinDirectory(
  line: string,
  directory: string,
): boolean {
  return new RegExp(`${escapeRegex(directory)}/[^\\s]+`).test(line);
}

export function extractFsUsageCall(line: string): string | undefined {
  return line.trim().split(/\s+/)[1];
}

export function classifyFsUsageLine(line: string): FsActivityKind {
  const rawCall = extractFsUsageCall(line)?.toLowerCase();
  if (!rawCall) return "other";
  const call = rawCall.replace(/\[.*$/, "").replace(/_nocancel$/, "");

  if (WRITE_CALLS.has(call)) return "write";
  if (METADATA_CALLS.has(call)) return "metadata";
  if (READ_CALLS.has(call)) return "read";

  if (call === "open" || call === "openat") {
    return /\([^)]*W[^)]*\)/.test(line) ? "write" : "read";
  }

  return "other";
}
