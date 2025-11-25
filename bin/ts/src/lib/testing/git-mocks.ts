import type { SpawnSyncReturns } from "child_process";
import { vi } from "vitest";

export function createGitCommandMock(
  commandMap: Record<string, string | Error>,
) {
  return (args: string[], silent = false): string => {
    const command = args.join(" ");
    const result = commandMap[command];

    if (result instanceof Error) {
      if (!silent) throw result;
      return "";
    }

    return result || "";
  };
}

export function createGitSafeMock(
  commandMap: Record<
    string,
    { stdout?: string; stderr?: string; status?: number }
  >,
) {
  return (args: string[]) => {
    const command = args.join(" ");
    const result = commandMap[command] || {};

    return {
      stdout: result.stdout || "",
      stderr: result.stderr || "",
      status: result.status ?? 0,
    };
  };
}

export function mockExecSync(
  commandMap: Record<string, string | Error>,
): ReturnType<typeof vi.fn> {
  return vi.fn((command: string | Buffer) => {
    const cmdStr = typeof command === "string" ? command : String(command);
    const result = commandMap[cmdStr];

    if (result instanceof Error) {
      throw result;
    }

    return Buffer.from(result || "");
  });
}

export function mockSpawnSync(
  commandMap: Record<
    string,
    { stdout?: string; stderr?: string; status?: number }
  >,
): ReturnType<typeof vi.fn> {
  return vi.fn((command: string, args: string[]) => {
    const cmdStr = `${command} ${
      Array.isArray(args) ? args.join(" ") : ""
    }`.trim();
    const result = commandMap[cmdStr] || {};

    return {
      stdout: Buffer.from(result.stdout || ""),
      stderr: Buffer.from(result.stderr || ""),
      status: result.status ?? 0,
      signal: null,
      error: undefined,
      pid: 0,
      output: [
        null,
        Buffer.from(result.stdout || ""),
        Buffer.from(result.stderr || ""),
      ],
    } as SpawnSyncReturns<Buffer>;
  });
}
