#!/usr/local/bin/node

import { spawnSync } from 'child_process';

function openGoogleMeet() {
  const command = 'open'
  const args = [
    '-a',
    '/Users/benbernard/Applications/Chrome Apps.localized/Google Meet.app'
  ]

  spawnSync(command, args, { stdio: 'inherit' })
}

function openUrl(url) {
  const command = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
  const args = [
    '-g',
    '--args',
    '--profile-directory=Default',
    url
  ]

  spawnSync(command, args, { stdio: 'inherit' })
}

openGoogleMeet();

if (process.argv.length < 3) {
  console.log('Usage: openMeetAndUrl <url>')
  process.exit(1)
}

openUrl(process.argv[2])