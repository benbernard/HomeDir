#!/usr/bin/env tsx

import fs from "node:fs";
import path from "node:path";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

const HOME = process.env.HOME ?? "/";
const CLAUDE_CONFIG = path.join(HOME, ".claude.json");
const OPENCODE_CONFIG = path.join(HOME, ".config", "opencode", "opencode.json");

interface ClaudeMcpStdio {
  type: "stdio";
  command: string;
  args: string[];
  env: Record<string, string>;
}

interface ClaudeMcpHttp {
  type: "http";
  url: string;
}

type ClaudeMcp = ClaudeMcpStdio | ClaudeMcpHttp;

interface ClaudeProject {
  mcpServers?: Record<string, ClaudeMcp>;
  disabledMcpServers?: string[];
}

interface ClaudeConfig {
  mcpServers?: Record<string, ClaudeMcp>;
  disabledMcpServers?: string[];
  projects?: Record<string, ClaudeProject>;
}

interface OpencodeMcpLocal {
  type: "local";
  command: string[];
  enabled: boolean;
  environment?: Record<string, string>;
}

interface OpencodeMcpRemote {
  type: "remote";
  url: string;
  enabled: boolean;
  headers?: Record<string, string>;
}

type OpencodeMcp = OpencodeMcpLocal | OpencodeMcpRemote;

interface OpencodeConfig {
  $schema?: string;
  mcp?: Record<string, OpencodeMcp>;
  [key: string]: unknown;
}

function readClaudeConfig(): ClaudeConfig {
  const raw = fs.readFileSync(CLAUDE_CONFIG, "utf-8");
  return JSON.parse(raw) as ClaudeConfig;
}

function readOpencodeConfig(): OpencodeConfig {
  if (!fs.existsSync(OPENCODE_CONFIG)) {
    return { $schema: "https://opencode.ai/config.json" };
  }
  const raw = fs.readFileSync(OPENCODE_CONFIG, "utf-8");
  return JSON.parse(raw) as OpencodeConfig;
}

function writeOpencodeConfig(cfg: OpencodeConfig) {
  const dir = path.dirname(OPENCODE_CONFIG);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  fs.writeFileSync(OPENCODE_CONFIG, `${JSON.stringify(cfg, null, 2)}\n`);
}

function convertClaudeToOpencode(
  name: string,
  claude: ClaudeMcp,
  enabled: boolean,
): OpencodeMcp {
  if (claude.type === "stdio") {
    const cmd = [claude.command, ...(claude.args ?? [])];
    // Add -y for npx if not present, to match common opencode patterns
    if (cmd[0] === "npx" && cmd[1] !== "-y") {
      cmd.splice(1, 0, "-y");
    }
    const env = claude.env ?? {};
    return {
      type: "local",
      command: cmd,
      enabled,
      environment: Object.keys(env).length > 0 ? env : undefined,
    };
  }
  if (claude.type === "http") {
    return {
      type: "remote",
      url: claude.url,
      enabled,
    };
  }
  throw new Error(
    `Unknown MCP type for ${name}: ${(claude as { type: string }).type}`,
  );
}

function getProjectMcpServers(
  claude: ClaudeConfig,
  projectPath?: string,
): { servers: Record<string, ClaudeMcp>; disabled: string[] } {
  if (projectPath) {
    const proj = claude.projects?.[projectPath];
    if (!proj) {
      throw new Error(`Project not found in Claude config: ${projectPath}`);
    }
    return {
      servers: proj.mcpServers ?? {},
      disabled: proj.disabledMcpServers ?? [],
    };
  }
  return {
    servers: claude.mcpServers ?? {},
    disabled: claude.disabledMcpServers ?? [],
  };
}

function syncMcps(
  claude: ClaudeConfig,
  opencode: OpencodeConfig,
  opts: { project?: string; only?: string; force?: boolean },
): { added: string[]; updated: string[]; unchanged: string[] } {
  const { servers, disabled } = getProjectMcpServers(claude, opts.project);
  const disabledSet = new Set(disabled);

  if (!opencode.mcp) {
    opencode.mcp = {};
  }

  const added: string[] = [];
  const updated: string[] = [];
  const unchanged: string[] = [];

  for (const [name, claudeMcp] of Object.entries(servers)) {
    if (opts.only && name !== opts.only) continue;

    const enabled = !disabledSet.has(name);
    const converted = convertClaudeToOpencode(name, claudeMcp, enabled);

    if (opencode.mcp[name]) {
      if (opts.force) {
        opencode.mcp[name] = converted;
        updated.push(name);
      } else {
        unchanged.push(name);
      }
      continue;
    }

    opencode.mcp[name] = converted;
    added.push(name);
  }

  if (
    opts.only &&
    added.length === 0 &&
    updated.length === 0 &&
    unchanged.length === 0
  ) {
    throw new Error(`MCP server '${opts.only}' not found in Claude config`);
  }

  return { added, updated, unchanged };
}

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .usage("$0 [name] [--project <path>]")
    .positional("name", {
      type: "string",
      describe:
        "Specific MCP server name to sync (syncs all missing if omitted)",
    })
    .option("project", {
      alias: "p",
      type: "string",
      describe: "Sync from a specific Claude project path instead of global",
    })
    .option("list", {
      alias: "l",
      type: "boolean",
      describe: "List available MCP servers in Claude config and exit",
      default: false,
    })
    .option("force", {
      alias: "f",
      type: "boolean",
      describe: "Overwrite existing MCP servers in opencode config",
      default: false,
    })
    .help()
    .alias("help", "h")
    .example("$0", "Sync all missing global MCP servers")
    .example("$0 playwright", "Sync only the 'playwright' MCP server")
    .example(
      "$0 -p /Users/benbernard/site",
      "Sync all missing from project 'site'",
    )
    .example("$0 -l", "List all available Claude MCP servers")
    .example("$0 -f", "Force-update all existing global MCP servers").argv;

  const claude = readClaudeConfig();

  if (argv.list) {
    console.log("Global MCP servers:");
    for (const name of Object.keys(claude.mcpServers ?? {})) {
      const disabled = claude.disabledMcpServers?.includes(name)
        ? " (disabled)"
        : "";
      console.log(`  ${name}${disabled}`);
    }
    if (claude.projects) {
      for (const [projPath, proj] of Object.entries(claude.projects)) {
        if (!proj.mcpServers || Object.keys(proj.mcpServers).length === 0)
          continue;
        console.log(`\nProject ${projPath}:`);
        for (const name of Object.keys(proj.mcpServers)) {
          const disabled = proj.disabledMcpServers?.includes(name)
            ? " (disabled)"
            : "";
          console.log(`  ${name}${disabled}`);
        }
      }
    }
    return;
  }

  const opencode = readOpencodeConfig();
  const only = argv._[0] as string | undefined;

  // If no project specified and no global MCPs, suggest projects that have MCPs
  if (!argv.project && !only) {
    const hasGlobal = Object.keys(claude.mcpServers ?? {}).length > 0;
    if (!hasGlobal) {
      const projectsWithMcps = Object.entries(claude.projects ?? {}).filter(
        ([, proj]) =>
          proj.mcpServers && Object.keys(proj.mcpServers).length > 0,
      );
      if (projectsWithMcps.length > 0) {
        console.log("No global MCP servers found in Claude config.");
        console.log("\nProjects with MCP servers:");
        for (const [projPath, proj] of projectsWithMcps) {
          console.log(
            `  --project ${projPath}  (${Object.keys(proj.mcpServers!).join(
              ", ",
            )})`,
          );
        }
        console.log(
          "\nRun with --project <path> to sync project-specific MCPs.",
        );
      }
    }
  }

  const { added, updated, unchanged } = syncMcps(claude, opencode, {
    project: argv.project,
    only,
    force: argv.force,
  });

  const changed = added.length > 0 || updated.length > 0;

  if (added.length > 0) {
    console.log(`Added ${added.length} MCP server(s):`);
    for (const name of added) {
      console.log(`  + ${name}`);
    }
  }

  if (updated.length > 0) {
    console.log(`Updated ${updated.length} existing MCP server(s):`);
    for (const name of updated) {
      console.log(`  ~ ${name}`);
    }
  }

  if (unchanged.length > 0) {
    console.log(
      `Skipped ${unchanged.length} already existing (use --force to overwrite):`,
    );
    for (const name of unchanged) {
      console.log(`  = ${name}`);
    }
  }

  if (added.length === 0 && updated.length === 0 && unchanged.length === 0) {
    console.log("No MCP servers to sync.");
  }

  if (changed) {
    writeOpencodeConfig(opencode);
    console.log(`\nConfig written to: ${OPENCODE_CONFIG}`);
    console.log("Restart opencode for changes to take effect.");
  }
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
