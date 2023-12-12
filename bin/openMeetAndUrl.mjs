#!/usr/local/bin/node

import { spawnSync } from 'child_process';

function openGoogleMeet() {
  const command = 'open'
  const args = [
    '-a',
    '/Users/benbernard/Applications/Chrome Apps.localized/Google Meet.app'
  ]

  // console.log(`Running ${command} ${args.join(' ')}`);
  spawnSync(command, args, { stdio: 'inherit' })
  spawnSync('sleep', [2], { stdio: 'inherit' })
}

function openUrl(url) {
  const command = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  const args = [
    '-g',
    '--args',
    '--profile-directory=Default',
    url
  ]

  // console.log(`Running ${command} ${args.join(' ')}`);
  spawnSync(command, args, { stdio: 'inherit' })
}

// Find if the Google Meet.app is running
function isGoogleMeetRunning() {
  const command = 'ps'
  const args = [
    '-ax',
    '-o',
    'command'
  ]

  const result = spawnSync(command, args, { stdio: 'pipe' })
  const output = result.stdout.toString()

  return output.includes('Google Meet.app/Contents/MacOS/app_mode_loader')
}

function main() {
  if (!isGoogleMeetRunning()) {
    openGoogleMeet();
  }

  if (process.argv.length < 3) {
    console.log('Usage: openMeetAndUrl <url>')
    process.exit(1)
  }

  openUrl(process.argv[2])
}

main();