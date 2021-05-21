#!/usr/bin/env zsh

set -u
set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RESET='\033[0m'

local -a MAKE_ARGS=("${@}")

findRoot() {
  root=`git rev-parse --show-toplevel`
  if [[ ! -e ${root}/go.sum ]]; then
    echo "Did not find go.sum in ${root}"
    exit 1
  fi
  ROOT_DIR=${root}
}

runTest() {
  echo

  afplay /System/Library/Sounds/Blow.aiff -r 5 -v 0.4 &
  echo "${YELLOW}==========  Running Tests =========${RESET}"
  if make "${MAKE_ARGS[@]}"; then
    echo "${GREEN}==========  BUILD SUCCEEDED =========${RESET}"
    afplay /System/Library/Sounds/Ping.aiff -v 0.4 -r 2 &
  else
    echo "${RED}==========  BUILD FAILED =========${RESET}"
    say -r 600 -v Moira '[[volm 0.5]] Failed'
  fi

  echo
}

findRoot
echo "Found repo ${ROOT_DIR}"
echo "Using make args ${MAKE_ARGS}"

runTest

while (true) {
  # Wiat for a change
  fswatch -1 ${ROOT_DIR}
  runTest

  # Sleep so you can kill
  echo; echo
  sleep 1
}
