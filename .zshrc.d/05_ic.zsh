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
  local -a subcommands tmux_subcommands
  local curcontext="$curcontext" state line
  typeset -A opt_args

  subcommands=(
    'clone:Clone a GitHub repo with SSH'
    'c:Clone a GitHub repo with SSH'
    'attach:Attach current repo to nested tmux session'
    'a:Attach current repo to nested tmux session'
    'tmux:Show and recall tmux inventory'
    't:Show and recall tmux inventory'
    '--help:Show help message'
    '-h:Show help message'
    'help:Show help message'
  )
  tmux_subcommands=(
    'renumber:Renumber tmux windows'
    'status:Show and refresh tmux inventory'
    'recall:Alias for tmux status'
    'refresh:Refresh tmux inventory quietly'
    'watch:Continuously refresh tmux inventory'
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
        tmux|t)
          if (( CURRENT == 2 )); then
            _describe 'tmux subcommand' tmux_subcommands
          else
            case $words[3] in
              status|s|recall|ls)
                _arguments \
                  '--json[Print machine-readable JSON]' \
                  '--cached[Use the saved snapshot without refreshing]'
                ;;
              refresh|r)
                _arguments '--quiet[Suppress refresh output]'
                ;;
              watch)
                _arguments \
                  '--interval[Refresh interval in seconds]:seconds:(10)' \
                  '--quiet[Suppress refresh output]'
                ;;
            esac
          fi
          ;;
      esac
      ;;
  esac
}

# compdef _ic ic  # Temporarily disabled due to compdef error
