# IC - Simple Git Clone & Attach Manager - TypeScript wrapper
# This wraps the TypeScript implementation at ~/bin/ic-bin

ic() {
  # Create a temporary file for command exchange
  local cmd_file=$(mktemp)

  # Run ic-bin with the command exchange file, let output flow normally
  ic-bin --shell-command-exchange "$cmd_file" "$@"
  local exit_code=$?

  # Read and execute commands from the file
  if [[ -f "$cmd_file" && -s "$cmd_file" ]]; then
    while IFS= read -r line; do
      # Extract command from JSON using jq (prefer) or sed fallback
      local cmd=""
      if command -v jq &> /dev/null; then
        cmd=$(echo "$line" | jq -r '.run' 2>/dev/null)
      fi

      if [[ -z "$cmd" ]]; then
        # Fallback: use sed with proper newline handling
        cmd=$(echo "$line" | sed -E 's/^\{"run":"(.*)"\}$/\1/' | sed 's/\\"/"/g' | sed 's/\\n/\n/g')
      fi

      # Execute the command
      if [[ -n "$cmd" ]]; then
        # For multi-line commands (like heredocs), write to temp file and execute
        if [[ "$cmd" == *$'\n'* ]]; then
          local exec_script=$(mktemp)
          echo "$cmd" > "$exec_script"
          zsh "$exec_script"
          rm -f "$exec_script"
        else
          # Single-line commands can use eval
          eval "$cmd"
        fi
      fi
    done < "$cmd_file"
  fi

  # Clean up
  rm -f "$cmd_file"

  return $exit_code
}

# Add completion for ic command
_ic() {
  local -a subcommands
  local curcontext="$curcontext" state line
  typeset -A opt_args

  subcommands=(
    'clone:Clone a GitHub repo with SSH'
    'c:Clone a GitHub repo with SSH'
    'attach:Attach current repo to nested tmux session'
    'a:Attach current repo to nested tmux session'
    '--help:Show help message'
    '-h:Show help message'
    'help:Show help message'
  )

  _arguments -C \
    '1: :->subcommand' \
    '*::arg:->args'

  case $state in
    subcommand)
      _describe 'ic subcommand' subcommands
      ;;
    args)
      case $line[1] in
        clone|c)
          _message 'user/repo or repo'
          ;;
        attach|a)
          _arguments \
            '--force[Recreate session even if it exists]' \
            '--resume[Resume existing session (fail if not exists or attached)]'
          ;;
      esac
      ;;
  esac
}

# compdef _ic ic  # Temporarily disabled due to compdef error
