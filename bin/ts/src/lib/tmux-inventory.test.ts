import { mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { afterEach, describe, expect, it } from "vitest";
import {
  type TmuxInventory,
  formatTmuxInventory,
  identifyAgentProcess,
  readTmuxInventory,
  writeTmuxInventory,
} from "./tmux-inventory";

const tempDirectories: string[] = [];

afterEach(() => {
  for (const directory of tempDirectories.splice(0)) {
    rmSync(directory, { recursive: true, force: true });
  }
});

describe("identifyAgentProcess", () => {
  it.each([
    ["claude", "claude", "--resume session-123"],
    ["codex", "/opt/homebrew/bin/codex", "exec --json"],
    ["pi", "node", "/usr/local/bin/pi-coding-agent --session abc"],
    ["opencode", "opencode", "serve --hostname 127.0.0.1"],
  ])("identifies %s processes", (expected, command, args) => {
    expect(identifyAgentProcess({ command, args })).toBe(expected);
  });

  it("does not classify unrelated processes", () => {
    expect(
      identifyAgentProcess({
        command: "node",
        args: "./scripts/claude-notify.ts",
      }),
    ).toBeNull();
  });
});

describe("tmux inventory persistence and formatting", () => {
  it("round-trips an inventory and renders its mappings", () => {
    const directory = mkdtempSync(join(tmpdir(), "tmux-inventory-test-"));
    tempDirectories.push(directory);
    const path = join(directory, "inventory.json");
    const inventory: TmuxInventory = {
      schemaVersion: 1,
      updatedAt: new Date().toISOString(),
      outerSocket: "default",
      nestedSocket: "nested",
      outer: [
        {
          sessionId: "$0",
          sessionName: "default",
          attached: true,
          windows: [
            {
              windowId: "@1",
              windowIndex: 1,
              windowName: "ic: api",
              active: true,
              kind: "ic",
              currentDirectory: "/Users/test/repos/api",
              nestedSessionNames: ["api"],
              panes: [
                {
                  paneId: "%1",
                  paneIndex: 0,
                  pid: 100,
                  tty: "/dev/ttys001",
                  command: "zsh",
                  title: "ic: api",
                  directory: "/Users/test/repos/api",
                  active: true,
                  agents: [
                    {
                      name: "claude",
                      pid: 200,
                      command: "claude",
                      sessionId: "session-123",
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
      nested: [
        {
          sessionId: "api",
          sessionName: "api",
          attached: true,
          windows: [],
        },
      ],
      attachments: [
        {
          outerSessionId: "$0",
          outerSessionName: "default",
          outerWindowId: "@1",
          outerWindowIndex: 1,
          outerWindowName: "ic: api",
          outerPaneId: "%1",
          nestedSessionId: "api",
          nestedSessionName: "api",
          nestedClientPid: 300,
          nestedClientTty: "/dev/ttys001",
        },
      ],
    };

    writeTmuxInventory(inventory, path);

    expect(readTmuxInventory(path)).toEqual(inventory);
    const rendered = formatTmuxInventory(inventory, {
      homeDirectory: "/Users/test",
    });
    expect(rendered).toContain("ic: api");
    expect(rendered).toContain("claude session-123");
    expect(rendered).toContain("~/repos/api");
    expect(rendered).toContain("default:1 @1 ic: api -> api");
  });
});
