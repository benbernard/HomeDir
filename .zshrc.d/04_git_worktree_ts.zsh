# Git worktree management function - TypeScript wrapper
# This wraps the TypeScript implementation at ~/bin/wt-bin

wt() {
  # Capture the output from the TypeScript binary
  local output=$(wt-bin "$@" 2>&1)
  local exit_code=$?

  # Check if the output contains a directory change directive
  if [[ "$output" =~ __WT_CD__(.+)$ ]]; then
    local target_path="${match[1]}"
    # Remove the directive from output
    output="${output%__WT_CD__*}"
    # Print the output (without the directive)
    if [[ -n "$output" ]]; then
      echo "$output"
    fi
    # Change to the target directory
    cd "$target_path"
  else
    # No directory change, just print the output
    echo "$output"
  fi

  return $exit_code
}

# Add completion for wt command (same as before)
_wt() {
  local -a subcommands
  local curcontext="$curcontext" state line
  typeset -A opt_args

  subcommands=(
    'clone:Clone a GitHub repo and create master worktree'
    '-b:Create new branch and worktree'
    'list:List all worktrees'
    'ls:List all worktrees'
    'remove:Remove a worktree'
    'rm:Remove a worktree'
    '--help:Show help message'
    '-h:Show help message'
    'help:Show help message'
  )

  _arguments -C \
    '(-v --verbose)'{-v,--verbose}'[Show debug output]' \
    '1: :->subcommand' \
    '*::arg:->args'

  case $state in
    subcommand)
      _describe 'wt subcommand' subcommands
      ;;
    args)
      case $line[1] in
        -b)
          # For -b, complete with git branch names
          if [[ $CURRENT -eq 1 ]]; then
            # First argument after -b: new branch name (no completion)
            _message 'new branch name'
          elif [[ $CURRENT -eq 2 ]]; then
            # Second argument: base branch (complete from existing branches)
            local -a branches
            branches=(${(f)"$(git branch --format='%(refname:short)' 2>/dev/null)"})
            _describe 'base branch' branches
          fi
          ;;
        clone)
          _message 'user/repo or repo'
          ;;
        remove|rm)
          # Complete with worktree paths
          local -a worktrees
          worktrees=(${(f)"$(git worktree list --porcelain 2>/dev/null | awk '/^worktree / {print substr($0, 10)}')"})
          _describe 'worktree path' worktrees
          ;;
      esac
      ;;
  esac
}

compdef _wt wt

# Worktree attach - attach a worktree to a nested tmux session
# (keeping the same implementation as before)
wta() {
  if ! command -v fzf &> /dev/null; then
    echo "Error: fzf is not installed"
    return 1
  fi

  # Check if we're in tmux
  if [[ -z "$TMUX" ]]; then
    echo "Error: Not in a tmux session"
    return 1
  fi

  # Check if we're in a worktree parent directory first (has bare/ subdir)
  local use_bare_subdir=0
  if [[ -d "./bare/.git" ]] || [[ -f "./bare/HEAD" ]]; then
    # We're in a worktree parent, use the bare directory
    use_bare_subdir=1
    echo "DEBUG: Detected worktree parent directory, using bare/"
  else
    # Check if we're in a git repository
    if ! git rev-parse --git-common-dir &>/dev/null; then
      echo "Error: Not in a git repository or worktree parent directory"
      return 1
    fi
  fi

  # Get list of existing tmux sessions
  local sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)
  typeset -A session_exists

  echo "DEBUG: Existing tmux sessions:"
  for session_name in ${(f)sessions}; do
    session_exists[$session_name]=1
    echo "  - '$session_name'"
  done
  echo ""

  # Get worktrees list (use -C to run from the bare dir if we're in parent)
  local worktree_data
  if [[ $use_bare_subdir -eq 1 ]]; then
    worktree_data=$(git -C bare worktree list --porcelain)
  else
    worktree_data=$(git worktree list --porcelain)
  fi

  # Parse worktrees and filter out ones with existing sessions
  local worktrees=""
  local path="" branch=""
  local is_bare=0
  echo "DEBUG: Processing worktrees:"
  for line in ${(f)worktree_data}; do
    if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
      path="${match[1]}"
      is_bare=0
    elif [[ "$line" == "bare" ]]; then
      is_bare=1
    elif [[ "$line" =~ ^branch\ refs/heads/(.+)$ ]]; then
      branch="${match[1]}"
    elif [[ -z "$line" && -n "$path" ]]; then
      # Empty line marks end of entry
      if [[ $is_bare -eq 1 ]]; then
        echo "  Worktree: BARE (skipping)"
      elif [[ -n "$branch" ]]; then
        echo "  Worktree: branch='$branch', path='$path'"
        if [[ -z "${session_exists[$branch]}" ]]; then
          echo "    -> UNATTACHED (adding to list)"
          worktrees+="$(printf "%-20s %s\n" "$branch" "$path")"
        else
          echo "    -> attached (session exists)"
        fi
      fi
      path=""
      branch=""
      is_bare=0
    fi
  done

  # Handle last entry if data doesn't end with blank line
  if [[ -n "$path" ]]; then
    if [[ $is_bare -eq 1 ]]; then
      echo "  Worktree (last): BARE (skipping)"
    elif [[ -n "$branch" ]]; then
      echo "  Worktree (last): branch='$branch', path='$path'"
      if [[ -z "${session_exists[$branch]}" ]]; then
        echo "    -> UNATTACHED (adding to list)"
        worktrees+="$(printf "%-20s %s\n" "$branch" "$path")"
      else
        echo "    -> attached (session exists)"
      fi
    fi
  fi
  echo ""

  if [[ -z "$worktrees" ]]; then
    echo "No unattached worktrees found"
    echo "All worktrees have active tmux sessions"
    return 0
  fi

  local selected=$(echo "$worktrees" | fzf \
    --header='Select worktree to attach' \
    --preview="
      export PATH='$PATH'
      wt_path=\$(echo {} | awk '{print \$NF}')
      wt_branch=\$(echo {} | awk '{print \$1}')
      echo \"Branch: \$wt_branch\"
      echo \"Path: \$wt_path\"
      echo \"\"
      cd \"\$wt_path\" && command git log --color --oneline --decorate -10
    ")

  if [[ -z "$selected" ]]; then
    return 0
  fi

  # Extract branch name and path
  local branch_name=$(echo "$selected" | awk '{print $1}')
  local worktree_path=$(echo "$selected" | awk '{print $NF}')

  echo "Attaching worktree: $branch_name"
  echo "Path: $worktree_path"

  # Create outer tmux window and set up nested session
  # The command will:
  # 1. Create the inner session (if it doesn't exist)
  # 2. Create a new window in the inner session
  # 3. Set the outer window title
  # 4. Attach to the inner session
  tmux new-window -n "$branch_name" -c "$worktree_path" \
    "zsh -c 'TMUX=\"\" tmux new-session -d -s \"$branch_name\" -c \"$worktree_path\" 2>/dev/null; \
             TMUX=\"\" tmux new-window -t \"$branch_name\" -d -c \"$worktree_path\"; \
             echo -e -n \"\\033knt: $branch_name\\033\\\\\"; \
             TMUX=\"\" exec tmux attach-session -t \"$branch_name\"'"
}
