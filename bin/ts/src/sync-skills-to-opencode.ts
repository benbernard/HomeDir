#!/usr/bin/env tsx

import fs from "node:fs";
import path from "node:path";
import yargs from "yargs";
import { hideBin } from "yargs/helpers";

const HOME = process.env.HOME ?? "/";
const SKILLS_DIR = path.join(HOME, ".config", "skillshare", "skills");
const OPENCODE_CONFIG = path.join(HOME, ".config", "opencode", "opencode.json");
const MANIFEST_FILE = path.join(
  HOME,
  ".config",
  "opencode",
  "skillshare-commands.json",
);

// Skills whose source path contains any of these substrings are excluded.
// Use this to block entire marketplace plugins by their path segment.
const BLACKLIST_SOURCES = [
  "external/gws", // Instacart marketplace GWS plugin (gws-*, recipe-*, persona-*)
];

interface SkillMetadata {
  source?: string;
}

interface SkillsMetadata {
  version: number;
  entries: Record<string, SkillMetadata>;
}

interface SkillFrontmatter {
  name: string;
  description?: string;
  blacklisted?: boolean;
}

interface OpencodeCommand {
  template: string;
  description?: string;
}

interface OpencodeConfig {
  $schema?: string;
  command?: Record<string, OpencodeCommand>;
  [key: string]: unknown;
}

function readSkillsMetadata(): Record<string, SkillMetadata> {
  const metaFile = path.join(SKILLS_DIR, ".metadata.json");
  if (!fs.existsSync(metaFile)) return {};
  const data = JSON.parse(
    fs.readFileSync(metaFile, "utf-8"),
  ) as SkillsMetadata;
  return data.entries ?? {};
}

function isSourceBlacklisted(source: string | undefined): boolean {
  if (!source) return false;
  return BLACKLIST_SOURCES.some((s) => source.includes(s));
}

function parseFrontmatter(content: string): Omit<SkillFrontmatter, "blacklisted"> | null {
  const match = content.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return null;

  const block = match[1];
  const result: Record<string, string> = {};

  for (const line of block.split("\n")) {
    const kv = line.match(/^(\w[\w-]*):\s*(.+)$/);
    if (kv) {
      result[kv[1]] = kv[2].trim().replace(/^["']|["']$/g, "");
    }
  }

  if (!result.name) return null;
  return { name: result.name, description: result.description };
}

function readSkills(): SkillFrontmatter[] {
  if (!fs.existsSync(SKILLS_DIR)) {
    throw new Error(`Skills dir not found: ${SKILLS_DIR}`);
  }

  const metadata = readSkillsMetadata();
  const skills: SkillFrontmatter[] = [];

  for (const entry of fs.readdirSync(SKILLS_DIR, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const skillMd = path.join(SKILLS_DIR, entry.name, "SKILL.md");
    if (!fs.existsSync(skillMd)) continue;
    const content = fs.readFileSync(skillMd, "utf-8");
    const fm = parseFrontmatter(content);
    if (!fm) continue;
    const source = metadata[entry.name]?.source;
    skills.push({ ...fm, blacklisted: isSourceBlacklisted(source) });
  }

  return skills;
}

function readOpencodeConfig(): OpencodeConfig {
  if (!fs.existsSync(OPENCODE_CONFIG)) {
    return { $schema: "https://opencode.ai/config.json" };
  }
  return JSON.parse(
    fs.readFileSync(OPENCODE_CONFIG, "utf-8"),
  ) as OpencodeConfig;
}

function writeOpencodeConfig(cfg: OpencodeConfig) {
  fs.writeFileSync(OPENCODE_CONFIG, `${JSON.stringify(cfg, null, 2)}\n`);
}

function readManifest(): Set<string> {
  if (!fs.existsSync(MANIFEST_FILE)) return new Set();
  const data = JSON.parse(fs.readFileSync(MANIFEST_FILE, "utf-8")) as string[];
  return new Set(data);
}

function writeManifest(names: Set<string>) {
  fs.writeFileSync(
    MANIFEST_FILE,
    `${JSON.stringify([...names].sort(), null, 2)}\n`,
  );
}

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .usage("$0 [options]")
    .option("dry-run", {
      alias: "n",
      type: "boolean",
      describe: "Preview changes without writing",
      default: false,
    })
    .option("list", {
      alias: "l",
      type: "boolean",
      describe: "List all skills and exit",
      default: false,
    })
    .option("remove", {
      alias: "r",
      type: "boolean",
      describe: "Remove all skillshare-managed commands from opencode config",
      default: false,
    })
    .help()
    .alias("help", "h")
    .example("$0", "Sync all skills to opencode commands")
    .example("$0 --dry-run", "Preview without writing")
    .example("$0 --remove", "Remove all managed commands").argv;

  const skills = readSkills();

  if (argv.list) {
    const active = skills.filter((s) => !s.blacklisted && s.description);
    const blocked = skills.filter((s) => s.blacklisted);
    console.log(
      `Found ${active.length} active skills (${blocked.length} blacklisted):\n`,
    );
    for (const s of active) {
      console.log(`  ${s.name.padEnd(35)} ${s.description}`);
    }
    if (blocked.length > 0) {
      console.log(`\nBlacklisted (source matches: ${BLACKLIST_SOURCES.join(", ")}):`);
      for (const s of blocked) console.log(`  ${s.name}`);
    }
    return;
  }

  const opencode = readOpencodeConfig();
  if (!opencode.command) opencode.command = {};
  const previouslyManaged = readManifest();

  if (argv.remove) {
    const removed: string[] = [];
    for (const name of previouslyManaged) {
      if (opencode.command[name]) {
        delete opencode.command[name];
        removed.push(name);
      }
    }
    if (removed.length === 0) {
      console.log("No managed commands found to remove.");
      return;
    }
    console.log(`Removed ${removed.length} command(s):`);
    for (const n of removed) console.log(`  - ${n}`);
    if (!argv.dryRun) {
      writeOpencodeConfig(opencode);
      writeManifest(new Set());
      console.log(`\nConfig written to: ${OPENCODE_CONFIG}`);
    } else {
      console.log("\n(dry run — no changes written)");
    }
    return;
  }

  const added: string[] = [];
  const updated: string[] = [];
  const removed: string[] = [];
  const skipped: string[] = [];
  const nowManaged = new Set<string>();

  for (const skill of skills) {
    if (skill.blacklisted || !skill.description) {
      skipped.push(skill.name);
      continue;
    }

    nowManaged.add(skill.name);

    const entry: OpencodeCommand = {
      description: skill.description,
      template: "{{input}}",
    };

    const existing = opencode.command[skill.name];
    if (existing) {
      const changed =
        existing.description !== entry.description ||
        existing.template !== entry.template;
      if (changed) {
        opencode.command[skill.name] = entry;
        updated.push(skill.name);
      }
    } else {
      opencode.command[skill.name] = entry;
      added.push(skill.name);
    }
  }

  // Remove stale managed commands (skill deleted, blacklisted, or lost description)
  for (const name of previouslyManaged) {
    if (!nowManaged.has(name) && opencode.command[name]) {
      delete opencode.command[name];
      removed.push(name);
    }
  }

  const changed = added.length > 0 || updated.length > 0 || removed.length > 0;

  if (added.length > 0) {
    console.log(`Added ${added.length} command(s):`);
    for (const n of added) console.log(`  + ${n}`);
  }
  if (updated.length > 0) {
    console.log(`Updated ${updated.length} command(s):`);
    for (const n of updated) console.log(`  ~ ${n}`);
  }
  if (removed.length > 0) {
    console.log(`Removed ${removed.length} stale command(s):`);
    for (const n of removed) console.log(`  - ${n}`);
  }
  if (skipped.length > 0) {
    console.log(`Skipped ${skipped.length} (blacklisted or no description).`);
  }
  if (!changed) {
    console.log("Already up to date.");
    return;
  }

  if (argv.dryRun) {
    console.log("\n(dry run — no changes written)");
    return;
  }

  writeOpencodeConfig(opencode);
  writeManifest(nowManaged);
  console.log(`\nConfig written to: ${OPENCODE_CONFIG}`);
  console.log(`Manifest written to: ${MANIFEST_FILE}`);
  console.log("Restart opencode for changes to take effect.");
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
