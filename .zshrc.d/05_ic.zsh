# IC - Simple Git Clone & Attach Manager - TypeScript wrapper
# This wraps the TypeScript implementation at ~/bin/ts/dist/ic

ic() {
  # Create a temporary script file
  local script_file=$(mktemp)

  # Run ic with the script file path, let output flow normally
  command ic --shell-integration-script "$script_file" "$@"
  local exit_code=$?

  # Execute the script if it exists and is not empty
  if [[ -f "$script_file" && -s "$script_file" ]]; then
    # Always source - scripts can use subshells for isolation if needed
    source "$script_file"
  fi

  # Clean up
  rm -f "$script_file"

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
            '--force[Detach other clients and attach]'
          ;;
      esac
      ;;
  esac
}

# compdef _ic ic  # Temporarily disabled due to compdef error
