#!/usr/bin/env tsx

import { readFileSync } from 'fs';
import yargs from 'yargs';
import { hideBin } from 'yargs/helpers';

async function main() {
  const argv = await yargs(hideBin(process.argv))
    .usage('Usage: $0 <logfile>')
    .demandCommand(1, 'Please provide a log file')
    .help()
    .alias('help', 'h')
    .argv;

  const logFile = argv._[0] as string;
  const content = readFileSync(logFile, 'utf-8');
  const lines = content.split('\n');

  interface Entry {
    timestamp: number;
    file: string;
  }

  const entries: Entry[] = [];

  for (const line of lines) {
    // Parse format: +TIMESTAMP LOCATION> command
    const match = line.match(/^\+(\d+\.\d+)\s+(.+?)>/);
    if (match) {
      const [, timestamp, location] = match;
      // Extract file from location (before :line)
      const file = location.split(':')[0];
      entries.push({
        timestamp: parseFloat(timestamp),
        file,
      });
    }
  }

  if (entries.length === 0) {
    console.error('No log entries found');
    process.exit(1);
  }

  // Calculate time spent in each file
  const fileTimes = new Map<string, number>();

  for (let i = 0; i < entries.length - 1; i++) {
    const current = entries[i];
    const next = entries[i + 1];
    const duration = (next.timestamp - current.timestamp) * 1000; // Convert to ms

    fileTimes.set(current.file, (fileTimes.get(current.file) || 0) + duration);
  }

  // Sort by time
  const sorted = Array.from(fileTimes.entries())
    .sort((a, b) => b[1] - a[1]);

  console.log('\nCumulative time per file:\n');
  console.log('Time (ms) | File');
  console.log('-'.repeat(80));

  for (const [file, time] of sorted.slice(0, 40)) {
    const timeStr = time.toFixed(2).padStart(9);
    console.log(`${timeStr} | ${file}`);
  }

  const totalTime = (entries[entries.length - 1].timestamp - entries[0].timestamp) * 1000;
  console.log(`\nTotal startup time: ${totalTime.toFixed(2)}ms`);
}

main();
