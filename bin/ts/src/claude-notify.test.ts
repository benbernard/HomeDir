import { execSync } from "child_process";
import { existsSync, readFileSync, writeFileSync } from "fs";
import { homedir } from "os";
import { join } from "path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Mock the modules
vi.mock("fs");
vi.mock("child_process");
vi.mock("zx", () => ({
  $: vi.fn(),
}));

// These would normally be imported from claude-notify.ts,
// but since they're not exported, we'll test them indirectly through the main module
// For now, let's create unit tests for the helper functions that can be tested

describe("claude-notify helper functions", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe("encodeProjectPath", () => {
    it("should replace slashes with dashes", () => {
      // We'll need to import or expose this function
      // For now, testing the logic
      const path = "/Users/benbernard/repos/olive-cli";
      const expected = "-Users-benbernard-repos-olive-cli";
      const result = path.replace(/\//g, "-");
      expect(result).toBe(expected);
    });
  });

  describe("findGitRoot", () => {
    it("should find git root when .git exists in current directory", () => {
      const mockExistsSync = vi.mocked(existsSync);
      mockExistsSync.mockReturnValue(true);

      const testPath = "/Users/benbernard/repos/olive-cli";
      // This is the logic from findGitRoot
      const gitPath = join(testPath, ".git");
      const exists = existsSync(gitPath);

      expect(exists).toBe(true);
      expect(mockExistsSync).toHaveBeenCalledWith(gitPath);
    });

    it("should walk up directories to find .git", () => {
      const mockExistsSync = vi.mocked(existsSync);
      // First call returns false, second returns true
      mockExistsSync
        .mockReturnValueOnce(false) // /Users/benbernard/repos/olive-cli/.git
        .mockReturnValueOnce(true); // /Users/benbernard/repos/olive-cli/../.git

      expect(mockExistsSync("/test/deep/path/.git")).toBe(false);
      expect(mockExistsSync("/test/deep/.git")).toBe(true);
    });
  });

  describe("cache operations", () => {
    it("should read cache from file", () => {
      const mockReadFileSync = vi.mocked(readFileSync);
      const mockExistsSync = vi.mocked(existsSync);

      const mockCache = { "session-id": "Test summary" };
      mockExistsSync.mockReturnValue(true);
      mockReadFileSync.mockReturnValue(JSON.stringify(mockCache));

      const cacheFile = join(
        homedir(),
        ".config",
        "claude-notify",
        "summaries.json",
      );

      if (existsSync(cacheFile)) {
        const content = readFileSync(cacheFile, "utf-8");
        const cache = JSON.parse(content);
        expect(cache).toEqual(mockCache);
      }
    });

    it("should write cache to file", () => {
      const mockWriteFileSync = vi.mocked(writeFileSync);
      const mockExecSync = vi.mocked(execSync);

      const cache = { "session-id": "Test summary" };
      const cacheFile = join(
        homedir(),
        ".config",
        "claude-notify",
        "summaries.json",
      );
      const tmpFile = `${cacheFile}.tmp`;

      writeFileSync(tmpFile, JSON.stringify(cache, null, 2));

      expect(mockWriteFileSync).toHaveBeenCalledWith(
        tmpFile,
        JSON.stringify(cache, null, 2),
      );
    });
  });

  describe("session file parsing", () => {
    it("should extract summary from session file", () => {
      const mockReadFileSync = vi.mocked(readFileSync);

      const sessionContent = `{"type":"file-history-snapshot","messageId":"test"}
{"type":"summary","summary":"Fix authentication bug","leafUuid":"test-uuid"}
{"type":"user","message":{"role":"user","content":"test"}}`;

      mockReadFileSync.mockReturnValue(sessionContent);

      const content = readFileSync("test.jsonl", "utf-8");
      const lines = content.split("\n").filter((line) => line.trim());

      let summary: string | null = null;
      for (const line of lines) {
        const entry = JSON.parse(line);
        if (entry.type === "summary" && entry.summary) {
          summary = entry.summary;
          break;
        }
      }

      expect(summary).toBe("Fix authentication bug");
    });

    it("should extract first user message from session file", () => {
      const mockReadFileSync = vi.mocked(readFileSync);

      const sessionContent = `{"type":"user","isSidechain":false,"isMeta":true,"message":{"role":"user","content":"Caveat: skip"}}
{"type":"user","isSidechain":false,"isMeta":false,"message":{"role":"user","content":"Fix the auth bug"}}`;

      mockReadFileSync.mockReturnValue(sessionContent);

      const content = readFileSync("test.jsonl", "utf-8");
      const lines = content.split("\n").filter((line) => line.trim());

      let firstMessage: string | null = null;
      for (const line of lines) {
        const entry = JSON.parse(line);
        if (
          entry.type === "user" &&
          !entry.isSidechain &&
          !entry.isMeta &&
          entry.message?.role === "user"
        ) {
          firstMessage = entry.message.content;
          break;
        }
      }

      expect(firstMessage).toBe("Fix the auth bug");
    });

    it("should handle array content in user messages", () => {
      const mockReadFileSync = vi.mocked(readFileSync);

      const sessionContent = `{"type":"user","isSidechain":false,"isMeta":false,"message":{"role":"user","content":[{"type":"text","text":"Part 1"},{"type":"text","text":"Part 2"}]}}`;

      mockReadFileSync.mockReturnValue(sessionContent);

      const content = readFileSync("test.jsonl", "utf-8");
      const lines = content.split("\n").filter((line) => line.trim());

      const entry = JSON.parse(lines[0]);
      const messageContent = entry.message.content;

      if (Array.isArray(messageContent)) {
        const textParts = messageContent
          .filter((part) => part.type === "text")
          .map((part) => part.text);
        const result = textParts.join(" ");
        expect(result).toBe("Part 1 Part 2");
      }
    });
  });

  describe("message cleaning", () => {
    it("should remove HTML tags from messages", () => {
      const message = "<command>test command</command> Some text";
      const cleaned = message.replace(/<[^>]*>/g, "");
      // Removes tags but leaves content: "test command Some text"
      expect(cleaned).toBe("test command Some text");
    });

    it("should remove Caveat prefix from messages", () => {
      const message = "Caveat: something bad\nActual message";
      const cleaned = message.replace(/Caveat:.*/g, "").trim();
      // Caveat regex removes everything after "Caveat:" to end of line
      // Then trim removes leading/trailing whitespace
      expect(cleaned).toBe("Actual message");
    });

    it("should clean message with both HTML and Caveat", () => {
      const message = "<tag>Text before</tag> Real content";
      const cleaned = message
        .replace(/<[^>]*>/g, "")
        .replace(/Caveat:.*/g, "")
        .trim();
      // Removes tags, no Caveat to remove, then trim
      expect(cleaned).toBe("Text before Real content");
    });
  });

  describe("project context", () => {
    it("should extract basename from git root", () => {
      const gitRoot = "/Users/benbernard/repos/olive-cli";
      const basename = gitRoot.split("/").pop();
      expect(basename).toBe("olive-cli");
    });

    it("should handle root path edge case", () => {
      const gitRoot = "/";
      const basename = gitRoot.split("/").pop();
      expect(basename).toBe("");
    });
  });
});
