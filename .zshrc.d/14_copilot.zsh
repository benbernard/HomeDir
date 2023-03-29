# Originally from the github-copilot-cli itself (copilot alias $SHELL)
# Changed to not run the commands, instead insert it into the next command line

# check to see if github-copilot-cli is installed
if [[ ! -x "$(command -v github-copilot-cli)" ]]; then
  NODE_DIR=~/.nvm/versions/node/$(node --version)
  export "PATH=$PATH:${NODE_DIR}/bin"
fi

if [[ ! -x "$(command -v github-copilot-cli)" ]]; then
  echo "Install github copilot"
  echo "npm i -g @githubnext/github-copilot-cli"
fi



copilot_what-the-shell () {
  TMPFILE=$(mktemp);
  trap 'rm -f $TMPFILE' EXIT;
  if github-copilot-cli what-the-shell "$@" --shellout $TMPFILE; then
    if [ -e "$TMPFILE" ]; then
      FIXED_CMD=$(cat $TMPFILE);
      print -z "$FIXED_CMD";
      # eval "$FIXED_CMD"
    else
      echo "Apologies! Extracting command failed"
    fi
  else
    return 1
  fi
};

copilot_git-assist () {
  TMPFILE=$(mktemp);
  trap 'rm -f $TMPFILE' EXIT;
  if github-copilot-cli git-assist "$@" --shellout $TMPFILE; then
    if [ -e "$TMPFILE" ]; then
      FIXED_CMD=$(cat $TMPFILE);
      print -z "$FIXED_CMD";
      # eval "$FIXED_CMD"
    else
      echo "Apologies! Extracting command failed"
    fi
  else
    return 1
  fi
};

copilot_gh-assist () {
  TMPFILE=$(mktemp);
  trap 'rm -f $TMPFILE' EXIT;
  if github-copilot-cli gh-assist "$@" --shellout $TMPFILE; then
    if [ -e "$TMPFILE" ]; then
      FIXED_CMD=$(cat $TMPFILE);
      print -z "$FIXED_CMD";
      # eval "$FIXED_CMD"
    else
      echo "Apologies! Extracting command failed"
    fi
  else
    return 1
  fi
};

alias 'gh?'='copilot_gh-assist';
alias 'wts'='copilot_what-the-shell';
alias 'git?'='copilot_git-assist';
alias '??'='copilot_what-the-shell';
alias 'copilot=github-copilot-cli'
