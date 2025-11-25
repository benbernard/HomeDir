import { join } from "path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Mock fs module
vi.mock("fs", async () => {
  const actual = await vi.importActual<typeof import("fs")>("fs");
  return {
    ...actual,
    existsSync: vi.fn(),
    readFileSync: vi.fn(),
  };
});

import { existsSync, readFileSync } from "fs";
import {
  detectRepoFiles,
  detectWorkspace,
  getReposDir,
  loadIcConfig,
  parseGitHubInput,
  resolveSetupHooks,
} from "./ic";

describe("ic - GitHub URL Parsing", () => {
  it("should parse HTTPS GitHub URL", () => {
    const result = parseGitHubInput("https://github.com/user/repo");
    expect(result).toEqual({ user: "user", repo: "repo" });
  });

  it("should parse HTTPS GitHub URL with .git extension", () => {
    const result = parseGitHubInput("https://github.com/user/repo.git");
    expect(result).toEqual({ user: "user", repo: "repo" });
  });

  it("should parse SSH GitHub URL", () => {
    const result = parseGitHubInput("git@github.com:user/repo");
    expect(result).toEqual({ user: "user", repo: "repo" });
  });

  it("should parse SSH GitHub URL with .git extension", () => {
    const result = parseGitHubInput("git@github.com:user/repo.git");
    expect(result).toEqual({ user: "user", repo: "repo" });
  });

  it("should parse user/repo format", () => {
    const result = parseGitHubInput("user/repo");
    expect(result).toEqual({ user: "user", repo: "repo" });
  });

  it("should default to instacart for repo-only input", () => {
    const result = parseGitHubInput("myrepo");
    expect(result).toEqual({ user: "instacart", repo: "myrepo" });
  });

  it("should return null for invalid input", () => {
    expect(parseGitHubInput("")).toBeNull();
    expect(parseGitHubInput("invalid://url")).toBeNull();
    expect(parseGitHubInput("foo:bar")).toBeNull();
  });

  it("should handle trailing slashes", () => {
    const result = parseGitHubInput("https://github.com/user/repo/");
    expect(result).toEqual({ user: "user", repo: "repo" });
  });

  it("should handle HTTP URLs", () => {
    const result = parseGitHubInput("http://github.com/user/repo");
    expect(result).toEqual({ user: "user", repo: "repo" });
  });
});

describe("ic - Config Loading", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("should return defaults when config file does not exist", () => {
    vi.mocked(existsSync).mockReturnValue(false);

    const config = loadIcConfig();

    expect(config).toHaveProperty("autoDetect");
    expect(config.autoDetect).toEqual({
      "package.json": ["npm install"],
      Gemfile: ["bundle install"],
      "requirements.txt": ["pip install -r requirements.txt"],
      "go.mod": ["go mod download"],
    });
  });

  it("should load and parse .icrc.json config", () => {
    vi.mocked(existsSync).mockReturnValue(true);
    vi.mocked(readFileSync).mockReturnValue(
      JSON.stringify({
        hooks: {
          "user/repo": ["custom command"],
        },
        autoDetect: {
          "package.json": ["yarn install"],
        },
      }),
    );

    const config = loadIcConfig();

    expect(config.hooks).toEqual({
      "user/repo": ["custom command"],
    });
    expect(config.autoDetect).toEqual({
      "package.json": ["yarn install"],
    });
  });

  it("should merge config with defaults when autoDetect is missing", () => {
    vi.mocked(existsSync).mockReturnValue(true);
    vi.mocked(readFileSync).mockReturnValue(
      JSON.stringify({
        hooks: {
          "user/repo": ["custom command"],
        },
      }),
    );

    const config = loadIcConfig();

    expect(config.hooks).toEqual({
      "user/repo": ["custom command"],
    });
    expect(config.autoDetect).toEqual({
      "package.json": ["npm install"],
      Gemfile: ["bundle install"],
      "requirements.txt": ["pip install -r requirements.txt"],
      "go.mod": ["go mod download"],
    });
  });

  it("should return defaults when config file is invalid JSON", () => {
    vi.mocked(existsSync).mockReturnValue(true);
    vi.mocked(readFileSync).mockReturnValue("invalid json{");

    const config = loadIcConfig();

    expect(config).toHaveProperty("autoDetect");
    expect(config.autoDetect).toEqual({
      "package.json": ["npm install"],
      Gemfile: ["bundle install"],
      "requirements.txt": ["pip install -r requirements.txt"],
      "go.mod": ["go mod download"],
    });
  });
});

describe("ic - Setup Hooks Resolution", () => {
  it("should return exact match for repo identifier", () => {
    const config = {
      hooks: {
        "user/repo": ["npm install", "npm run build"],
      },
      autoDetect: {
        "package.json": ["npm install"],
      },
    };

    const result = resolveSetupHooks(config, "user/repo", ["package.json"]);
    expect(result).toEqual(["npm install", "npm run build"]);
  });

  it("should use autoDetect when no exact match", () => {
    const config = {
      hooks: {
        "different/repo": ["something"],
      },
      autoDetect: {
        "package.json": ["npm install"],
        Gemfile: ["bundle install"],
      },
    };

    const result = resolveSetupHooks(config, "user/repo", ["package.json"]);
    expect(result).toEqual(["npm install"]);
  });

  it("should combine commands from multiple detected files", () => {
    const config = {
      autoDetect: {
        "package.json": ["npm install"],
        Gemfile: ["bundle install"],
        "requirements.txt": ["pip install -r requirements.txt"],
      },
    };

    const result = resolveSetupHooks(config, "user/repo", [
      "package.json",
      "Gemfile",
    ]);
    expect(result).toEqual(["npm install", "bundle install"]);
  });

  it("should return empty array when no hooks match", () => {
    const config = {
      autoDetect: {
        "package.json": ["npm install"],
      },
    };

    const result = resolveSetupHooks(config, "user/repo", ["unknown.file"]);
    expect(result).toEqual([]);
  });

  it("should handle missing autoDetect config", () => {
    const config = {
      hooks: {
        "user/repo": ["npm install"],
      },
    };

    const result = resolveSetupHooks(config, "other/repo", ["package.json"]);
    expect(result).toEqual([]);
  });
});

describe("ic - File Detection", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("should detect package.json in directory", () => {
    vi.mocked(existsSync).mockImplementation((path) => {
      return String(path).endsWith("package.json");
    });

    const files = detectRepoFiles("/test/repo");
    expect(files).toEqual(["package.json"]);
  });

  it("should detect Gemfile in directory", () => {
    vi.mocked(existsSync).mockImplementation((path) => {
      return String(path).endsWith("Gemfile");
    });

    const files = detectRepoFiles("/test/repo");
    expect(files).toEqual(["Gemfile"]);
  });

  it("should detect requirements.txt in directory", () => {
    vi.mocked(existsSync).mockImplementation((path) => {
      return String(path).endsWith("requirements.txt");
    });

    const files = detectRepoFiles("/test/repo");
    expect(files).toEqual(["requirements.txt"]);
  });

  it("should detect go.mod in directory", () => {
    vi.mocked(existsSync).mockImplementation((path) => {
      return String(path).endsWith("go.mod");
    });

    const files = detectRepoFiles("/test/repo");
    expect(files).toEqual(["go.mod"]);
  });

  it("should detect multiple files", () => {
    vi.mocked(existsSync).mockImplementation((path) => {
      const pathStr = String(path);
      return (
        pathStr.endsWith("package.json") ||
        pathStr.endsWith("Gemfile") ||
        pathStr.endsWith("go.mod")
      );
    });

    const files = detectRepoFiles("/test/repo");
    expect(files).toEqual(["package.json", "Gemfile", "go.mod"]);
  });

  it("should return empty array when no files found", () => {
    vi.mocked(existsSync).mockReturnValue(false);

    const files = detectRepoFiles("/test/repo");
    expect(files).toEqual([]);
  });
});

describe("ic - Workspace Detection", () => {
  let reposDir: string;

  beforeEach(() => {
    vi.clearAllMocks();
    // Get repos dir with mocked cdrp check
    vi.mocked(existsSync).mockReturnValue(false); // No cdrp config
    reposDir = getReposDir(); // Will return default ~/repos
  });

  it("should detect workspace from nested path", () => {
    // Mock for getReposDir (cdrp config) and workspace detection
    vi.mocked(existsSync).mockImplementation((path) => {
      const pathStr = String(path);
      // Return false for cdrp config check
      if (pathStr.includes("cdrp_dir")) return false;
      // For nested paths, we don't need to check .git since parts.length >= 2
      return true;
    });

    const workspace = detectWorkspace(`${reposDir}/myFeature/ava`);
    expect(workspace).toBe("myFeature");
  });

  it("should detect workspace from workspace root without .git", () => {
    vi.mocked(existsSync).mockImplementation((path) => {
      const pathStr = String(path);
      // Return false for cdrp config
      if (pathStr.includes("cdrp_dir")) return false;
      // Workspace directory exists
      if (pathStr === `${reposDir}/myFeature`) return true;
      // But no .git directory
      if (pathStr === `${reposDir}/myFeature/.git`) return false;
      return false;
    });

    const workspace = detectWorkspace(`${reposDir}/myFeature`);
    expect(workspace).toBe("myFeature");
  });

  it("should return null for standalone repo (has .git)", () => {
    vi.mocked(existsSync).mockImplementation((path) => {
      const pathStr = String(path);
      // Return false for cdrp config
      if (pathStr.includes("cdrp_dir")) return false;
      // Directory exists and has .git
      if (pathStr === `${reposDir}/standalone-repo`) return true;
      if (pathStr === `${reposDir}/standalone-repo/.git`) return true;
      return false;
    });

    const workspace = detectWorkspace(`${reposDir}/standalone-repo`);
    expect(workspace).toBeNull();
  });

  it("should return null for path outside repos dir", () => {
    // No need to mock existsSync for this test - path check happens first
    vi.mocked(existsSync).mockImplementation((path) => {
      const pathStr = String(path);
      if (pathStr.includes("cdrp_dir")) return false;
      return false;
    });

    const workspace = detectWorkspace("/Users/test/other/path");
    expect(workspace).toBeNull();
  });

  it("should return null for repos dir itself", () => {
    vi.mocked(existsSync).mockImplementation((path) => {
      const pathStr = String(path);
      if (pathStr.includes("cdrp_dir")) return false;
      return false;
    });

    const workspace = detectWorkspace(reposDir);
    expect(workspace).toBeNull();
  });

  it("should detect workspace from deeply nested path", () => {
    vi.mocked(existsSync).mockImplementation((path) => {
      const pathStr = String(path);
      // Return false for cdrp config check
      if (pathStr.includes("cdrp_dir")) return false;
      // For deeply nested paths, we don't need to check .git since parts.length >= 2
      return true;
    });

    const workspace = detectWorkspace(
      `${reposDir}/myFeature/ava/src/components`,
    );
    expect(workspace).toBe("myFeature");
  });
});
