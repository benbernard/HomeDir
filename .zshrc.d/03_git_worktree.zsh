# Git worktree management function
wt() {
  local verbose=0
  local subcommand=""

  # Check for verbose flag
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose|-v)
        verbose=1
        shift
        ;;
      *)
        if [[ -z "$subcommand" ]]; then
          subcommand="$1"
        fi
        break
        ;;
    esac
  done

  case "$subcommand" in
    clone)
      # Clone a GitHub repo as bare and create master worktree
      shift
      local input="$1"

      if [[ -z "$input" ]]; then
        echo "Usage: wt clone <user/repo> or <repo>"
        echo "  If no user specified, defaults to 'instacart'"
        return 1
      fi

      # Parse input - handle user/repo or just repo
      local user repo
      if [[ "$input" =~ / ]]; then
        user="${input%%/*}"
        repo="${input##*/}"
      else
        user="instacart"
        repo="$input"
      fi

      # Construct GitHub URL
      local repo_url="git@github.com:${user}/${repo}.git"

      local repos_dir="$HOME/repos"
      local repo_dir="$repos_dir/$repo"

      # Handle directory collision by appending -wt
      if [[ -d "$repo_dir" ]]; then
        repo_dir="$repos_dir/${repo}-wt"
        echo "Directory $repos_dir/$repo already exists, using $repo_dir instead"
      fi

      local bare_dir="$repo_dir/bare"
      local master_dir="$repo_dir/master"

      # Create repo directory
      mkdir -p "$repo_dir"

      # Clone as bare repository
      echo "Cloning $repo_url as bare repository to $bare_dir..."
      git clone --bare "$repo_url" "$bare_dir"

      if [[ $? -ne 0 ]]; then
        echo "Error: Failed to clone repository"
        return 1
      fi

      # Configure fetch refspec for bare repository
      echo "Configuring remote fetch refspec..."
      cd "$bare_dir"
      git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'

      # Create master worktree
      echo "Creating master worktree at $master_dir..."
      cd "$bare_dir"
      git worktree add ../master master 2>/dev/null || git worktree add ../master main

      if [[ $? -eq 0 ]]; then
        echo "Successfully created worktree structure:"
        echo "  Bare repo: $bare_dir"
        echo "  Master worktree: $master_dir"
        cd "$master_dir"
      else
        echo "Error: Failed to create master worktree"
        return 1
      fi
      ;;

    -b)
      # Create a new branch and worktree
      shift
      local branch_name="$1"
      local base_branch="$2"

      if [[ -z "$branch_name" ]]; then
        echo "Usage: wt -b <branch-name> [base-branch]"
        echo "  Creates a new branch and worktree"
        echo "  base-branch defaults to current branch if not specified"
        return 1
      fi

      # Find the common git directory (the bare repo in a worktree setup)
      local git_dir=$(git rev-parse --absolute-git-dir 2>/dev/null)
      local git_common_dir=$(cd "$(git rev-parse --git-common-dir 2>/dev/null)" && pwd)

      if [[ -z "$git_common_dir" ]]; then
        echo "Error: Not in a git repository"
        return 1
      fi

      if [[ $verbose -eq 1 ]]; then
        echo "DEBUG: git_dir=$git_dir"
        echo "DEBUG: git_common_dir=$git_common_dir"
        echo "DEBUG: Are they equal? $([[ "$git_dir" == "$git_common_dir" ]] && echo YES || echo NO)"
        echo "DEBUG: Is git_dir a directory? $([[ -d "$git_dir" ]] && echo YES || echo NO)"
        echo "DEBUG: Config file exists? $([[ -f "$git_common_dir/config" ]] && echo YES || echo NO)"
        if [[ -f "$git_common_dir/config" ]]; then
          echo "DEBUG: bare = true in config? $(grep "bare = true" "$git_common_dir/config" 2>/dev/null || echo NONE)"
        fi
      fi

      # In a worktree setup, git_dir != git_common_dir (worktree points to common)
      # OR git_common_dir is a bare repo (has bare = true)
      # If they're equal and it's not bare, it's a regular repo
      local is_bare=$(grep -q "bare = true" "$git_common_dir/config" 2>/dev/null && echo "yes" || echo "no")

      if [[ "$git_dir" == "$git_common_dir" ]] && [[ "$is_bare" == "no" ]]; then
        echo "Warning: Not in a worktree environment!"
        echo "You're in a regular git repository. Consider using 'wt clone' to set up worktrees."
        echo ""
        echo "Current setup: Regular repository"
        echo "Worktree setup: Clone with 'wt clone <repo>' to enable worktrees"
        return 1
      fi

      # Get current branch if base_branch not specified
      if [[ -z "$base_branch" ]]; then
        base_branch=$(git branch --show-current)
        echo "Using current branch '$base_branch' as base"
      fi

      # Ensure fetch refspec is configured (for repos cloned before this change)
      local fetch_refspec=$(git config --get remote.origin.fetch)
      if [[ "$fetch_refspec" != "+refs/heads/*:refs/remotes/origin/*" ]]; then
        [[ $verbose -eq 1 ]] && echo "DEBUG: Configuring fetch refspec for remote.origin"
        git config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
      fi

      # Fetch from origin to update remote tracking branches
      echo "Fetching from origin to update remote tracking branches..."
      git fetch origin
      if [[ $? -ne 0 ]]; then
        echo "Warning: Failed to fetch from origin. Continuing anyway..."
      fi

      # In a worktree setup, create new worktrees as siblings
      # If bare repo is in a 'bare' subdirectory, create worktrees next to it
      # Otherwise, create them inside the git common dir (old style)
      local worktree_parent_dir="$git_common_dir"
      if [[ "$(basename "$git_common_dir")" == "bare" ]]; then
        worktree_parent_dir="$(dirname "$git_common_dir")"
        [[ $verbose -eq 1 ]] && echo "DEBUG: Detected 'bare' subdir, creating worktree in parent: $worktree_parent_dir"
      else
        [[ $verbose -eq 1 ]] && echo "DEBUG: Using old-style structure, creating worktree in git dir: $worktree_parent_dir"
      fi

      local worktree_dir="$worktree_parent_dir/$branch_name"
      [[ $verbose -eq 1 ]] && echo "DEBUG: Will create worktree at: $worktree_dir"

      # Check if worktree already exists
      if [[ -d "$worktree_dir" ]]; then
        echo "Worktree '$branch_name' already exists, switching to it..."
        cd "$worktree_dir"
        return 0
      fi

      # Check if branch already exists
      if git rev-parse --verify "$branch_name" &>/dev/null; then
        echo "Branch '$branch_name' already exists. Checking out existing branch in new worktree..."
        git worktree add "$worktree_dir" "$branch_name"
      else
        echo "Creating new branch '$branch_name' from '$base_branch'..."
        git worktree add -b "$branch_name" "$worktree_dir" "$base_branch"
      fi

      if [[ $? -eq 0 ]]; then
        echo "Successfully created worktree at $worktree_dir"
        cd "$worktree_dir"
      else
        echo "Error: Failed to create worktree"
        return 1
      fi
      ;;

    list|ls)
      # List all worktrees
      git worktree list
      ;;

    remove|rm)
      # Remove a worktree
      shift
      local worktree_path="$1"

      # Default to current directory if no path provided
      if [[ -z "$worktree_path" ]]; then
        worktree_path=$(pwd)
        echo "Removing current worktree: $worktree_path"
      fi

      # Check if we're in a git repository
      if ! git rev-parse --git-dir &>/dev/null; then
        echo "Error: Not in a git repository"
        return 1
      fi

      # Check for uncommitted changes
      if ! git diff-index --quiet HEAD --; then
        echo "Error: Cannot remove worktree with uncommitted changes"
        echo "Please commit or stash your changes first"
        echo ""
        echo "Uncommitted changes:"
        git status --short
        return 1
      fi

      # Check for untracked files
      if [[ -n $(git ls-files --others --exclude-standard) ]]; then
        echo "Warning: Worktree has untracked files"
        git ls-files --others --exclude-standard
        read "response?Remove anyway? (y/N) "
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
          echo "Removal cancelled"
          return 1
        fi
      fi

      git worktree remove "$worktree_path"
      ;;

    --help|-h|help)
      echo "Git Worktree Manager"
      echo ""
      echo "Usage:"
      echo "  wt [--verbose]                  Interactive worktree selector (fzf)"
      echo "  wt clone <user/repo>            Clone repo to ~/repos and create master worktree"
      echo "  wt clone <repo>                 Clone instacart/<repo> to ~/repos"
      echo "  wt -b <branch> [base]           Create new branch and worktree (base defaults to current)"
      echo "  wt list|ls                      List all worktrees"
      echo "  wt remove|rm [path]             Remove a worktree (defaults to current directory)"
      echo "  wt --help|-h|help               Show this help message"
      echo ""
      echo "Options:"
      echo "  --verbose, -v                   Show debug output"
      echo ""
      echo "Directory Structure:"
      echo "  ~/repos/myrepo/"
      echo "    ├── bare/                     Bare git repository"
      echo "    ├── master/                   Master worktree"
      echo "    └── feature-branch/           Other worktrees"
      echo ""
      echo "Examples:"
      echo "  wt clone user/repo              # Clone git@github.com:user/repo.git"
      echo "  wt clone myrepo                 # Clone git@github.com:instacart/myrepo.git"
      echo "  wt -b feature-123               # Create from current branch"
      echo "  wt -b feature-123 main          # Create from main branch"
      echo "  wt remove                       # Remove current worktree (checks for uncommitted changes)"
      echo "  wt remove /path/to/worktree     # Remove specific worktree"
      echo "  wt --verbose                    # Show debug output in interactive mode"
      return 0
      ;;

    "")
      # Interactive worktree selector with fzf
      [[ $verbose -eq 1 ]] && echo "DEBUG: Interactive mode triggered"

      if ! command -v fzf &> /dev/null; then
        echo "Error: fzf is not installed"
        return 1
      fi
      [[ $verbose -eq 1 ]] && echo "DEBUG: fzf found"

      local git_dir=$(git rev-parse --git-common-dir 2>/dev/null)
      if [[ -z "$git_dir" ]]; then
        echo "Error: Not in a git repository"
        return 1
      fi
      [[ $verbose -eq 1 ]] && echo "DEBUG: git_dir=$git_dir"

      # Get worktrees and format them for fzf
      if [[ $verbose -eq 1 ]]; then
        echo "DEBUG: Getting worktree list..."
        git worktree list --porcelain

        echo "DEBUG: After awk processing:"
        git worktree list --porcelain | awk '
          /^worktree / { path = substr($0, 10) }
          /^branch / { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
          /^$/ {
            if (path != "" && branch != "") {
              print path "|" branch
              path = ""
              branch = ""
            }
          }
          END {
            if (path != "" && branch != "") {
              print path "|" branch
            }
          }
        '
        echo "DEBUG: About to run fzf..."
      fi

      # Format output as "branch    path" for display
      local worktrees=$(git worktree list --porcelain | awk '
        /^worktree / { path = substr($0, 10) }
        /^branch / { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
        /^$/ {
          if (path != "" && branch != "") {
            # Format: branch (left-aligned), then path
            printf "%-20s %s\n", branch, path
            path = ""
            branch = ""
          }
        }
        END {
          if (path != "" && branch != "") {
            printf "%-20s %s\n", branch, path
          }
        }
      ')

      if [[ $verbose -eq 1 ]]; then
        echo "DEBUG: Formatted worktrees:"
        echo "$worktrees"
      fi

      local selected=$(echo "$worktrees" | fzf \
        --header='Select worktree to switch to' \
        --preview="
          export PATH='$PATH'
          wt_path=\$(echo {} | awk '{print \$NF}')
          wt_branch=\$(echo {} | awk '{print \$1}')
          echo \"Branch: \$wt_branch\"
          echo \"Path: \$wt_path\"
          echo \"\"
          cd \"\$wt_path\" && git log --color --pretty=format:'%C(red)%h%Creset %C(magenta)%ar%Creset %C(yellow)%an%Creset %Cgreen%s%Creset %C(cyan)%d%Creset' -10
        ")

      [[ $verbose -eq 1 ]] && echo "DEBUG: selected=$selected"

      if [[ -n "$selected" ]]; then
        # Extract path from the formatted line (everything after the branch name)
        local target_path=$(echo "$selected" | awk '{print $NF}')
        [[ $verbose -eq 1 ]] && echo "DEBUG: Changing to $target_path"
        cd "$target_path"
      fi
      ;;

    *)
      echo "Unknown subcommand: $subcommand"
      echo "Run 'wt --help' for usage information"
      return 1
      ;;
  esac
}

# Add completion for wt command
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
