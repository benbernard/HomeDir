#!/usr/bin/env zsh

set -u
set -eo pipefail

findRoot() {
  root=`git rev-parse --show-toplevel`
  if [[ ! -e ${root}/go.sum ]]; then
    echo "Did not find go.sum in ${root}"
    exit 1
  fi
  ROOT_DIR=${root}
}

runTest() {
  if make "$@"; then
    echo BUILD SUCCESSFUL
    afplay /System/Library/Sounds/Ping.aiff -v 0.4 -r 2 &
  else
    say -r 600 -v Moira '[[volm 0.5]] Failed'
  fi
}

findRoot
echo "Found repo ${ROOT_DIR}"

runTest

while (true) {
  # Wiat for a change
  fswatch -1 ${ROOT_DIR}
  if make "$@"; then
    echo BEEP && beep
  else
    echo FAILED
  fi

  # Sleep so you can kill
  sleep 1
}
