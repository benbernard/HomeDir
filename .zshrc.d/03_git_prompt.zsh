# Adapted from: https://gist.github.com/wolever/6525437
# 100% pure Bash (no forking) function to determine the name of the current git branch
function gitbranch() {
    export GITBRANCH=""

    local repo="${_GITBRANCH_LAST_REPO-}"
    local gitdir=""
    [[ ! -z "$repo" ]] && gitdir="$repo/.git"

    # If we don't have a last seen git repo, or we are in a different directory
    if [[ -z "$repo" || "$PWD" != "$repo"* || ! -e "$gitdir" ]]; then
        local cur="$PWD"
        while [[ ! -z "$cur" ]]; do
            if [[ -e "$cur/.git" ]]; then
                repo="$cur"
                gitdir="$cur/.git"
                break
            fi
            cur="${cur%/*}"
        done
    fi

    if [[ -z "$gitdir" ]]; then
        unset _GITBRANCH_LAST_REPO
        return 0
    fi
    export _GITBRANCH_LAST_REPO="${repo}"

    echo $(parsehead $gitdir)
}

function parsehead() {
    local head=""
    local branch=""
    local gitdir=$1

    if [[ -d $gitdir ]]; then
      read head < "$gitdir/HEAD"
      case "$head" in
          ref:*) #normal ref
              branch="${head##*/}"
              ;;
          "")
              branch=""
              ;;
          *) # Detached head
              branch="${head:0:7}"
              ;;
      esac
    elif [[ -e $gitdir && $2 != "NO" ]]; then
      # covers sub modules
      read head < "$gitdir"
      case "$head" in
        gitdir:*)
          newdir=$(echo $head | cut -d' ' -f2)
          ;;
      esac
      echo $(parsehead $newdir "NO")
    fi

    if [[ -z "$branch" ]]; then
        return 0
    fi
    export GITBRANCH="$branch"
    echo ${repo##*/}:$GITBRANCH
}
