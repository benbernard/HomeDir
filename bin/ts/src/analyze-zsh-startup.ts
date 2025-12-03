#!/usr/bin/env tsx

import { readFileSync } from 'fs';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';

interface LogEntry {
  timestamp: number;
  location: string;
  line: string;
}

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .usage('Usage: $0 <logfile>')
    .option('threshold', {
      alias: 't',
      type: 'number',
      description: 'Only show entries taking more than N milliseconds',
      default: 10,
    })
    .option('top', {
      alias: 'n',
      type: 'number',
      description: 'Show top N slowest entries',
      default: 20,
    })
    .demandCommand(1, 'Please provide a log file to analyze')
    .help()
    .alias('help', 'h')
    .example('$0 zsh_profile.xyz', 'Analyze zsh startup log file')
    .argv;

  const logFile = argv._[0] as string;

  try {
    const content = readFileSync(logFile, 'utf-8');
    const lines = content.split('\n');

    const entries: LogEntry[] = [];

    for (const line of lines) {
      // Parse format: +TIMESTAMP LOCATION> command
      const match = line.match(/^\+(\d+\.\d+)\s+(.+?)>\s+(.+)$/);
      if (match) {
        const [, timestamp, location, command] = match;
        entries.push({
          timestamp: parseFloat(timestamp),
          location,
          line: command,
        });
      }
    }

    if (entries.length === 0) {
      console.error('No log entries found. Make sure the file is a ZSH_CMD_LOGGING output.');
      process.exit(1);
    }

    // Calculate time differences
    interface TimedEntry {
      duration: number;
      location: string;
      line: string;
      timestamp: number;
    }

    const timedEntries: TimedEntry[] = [];
    for (let i = 0; i < entries.length - 1; i++) {
      const current = entries[i];
      const next = entries[i + 1];
      const duration = (next.timestamp - current.timestamp) * 1000; // Convert to ms

      timedEntries.push({
        duration,
        location: current.location,
        line: current.line,
        timestamp: current.timestamp,
      });
    }

    // Filter by threshold
    const filtered = timedEntries.filter(e => e.duration >= argv.threshold);

    // Sort by duration (descending)
    filtered.sort((a, b) => b.duration - a.duration);

    // Take top N
    const topN = filtered.slice(0, argv.top);

    console.log(`\nTop ${topN.length} slowest operations (threshold: ${argv.threshold}ms):\n`);
    console.log('Duration (ms) | Location | Command');
    console.log('-'.repeat(80));

    for (const entry of topN) {
      const durationStr = entry.duration.toFixed(2).padStart(12);
      const locationStr = entry.location.padEnd(30);
      const lineStr = entry.line.slice(0, 60);
      console.log(`${durationStr} | ${locationStr} | ${lineStr}`);
    }

    // Summary by file
    const byFile = new Map<string, number>();
    for (const entry of filtered) {
      // Extract file from location (e.g., "/path/file.zsh:23" -> "/path/file.zsh")
      const file = entry.location.split(':')[0];
      byFile.set(file, (byFile.get(file) || 0) + entry.duration);
    }

    const sortedByFile = Array.from(byFile.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 10);

    console.log(`\n\nTop 10 files by total time:\n`);
    console.log('Total Time (ms) | File');
    console.log('-'.repeat(80));

    for (const [file, time] of sortedByFile) {
      const timeStr = time.toFixed(2).padStart(15);
      console.log(`${timeStr} | ${file}`);
    }

    const totalTime = (entries[entries.length - 1].timestamp - entries[0].timestamp) * 1000;
    console.log(`\n\nTotal startup time: ${totalTime.toFixed(2)}ms`);

  } catch (error) {
    console.error(`Error reading log file: ${error}`);
    process.exit(1);
  }
}

main();
