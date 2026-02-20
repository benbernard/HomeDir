# Inspired by
# - https://github.com/junegunn/fzf/wiki/Examples#git
# - https://junegunn.kr/2016/07/fzf-git/

# fco - checkout git branch/tag
fzf_get_ref() {
  local tags branches target

  # Check if we're in a git repo
  if ! git rev-parse --git-dir &>/dev/null; then
    return 1
  fi

  # tags=$(
  #   git for-each-ref --sort=-committerdate refs/tags/ --format="%(refname:short)" |
  #   awk '{print "\x1b[31;1mtag\x1b[m\t" $1}'
  # ) || return
  #
  # localBranches=$(
  #   git for-each-ref --sort=-committerdate refs/heads/ --format="%(refname:short)" |
  #   sed "s/.* //"    | sed "s#remotes/[^/]*/##" |
  #   awk '{print "\x1b[34;1mlocal\x1b[m\t" $1}'
  # ) || return
  #
  # remoteBranches=$(
  #   git for-each-ref --sort=-committerdate refs/remotes/ --format="%(refname:short)" |
  #   sed "s/.* //"    | sed "s#remotes/[^/]*/##" |
  #   awk '{print "\x1b[34;1mremote\x1b[m\t" $1}'
  # ) || return
  #
  # target=$(
  #   (echo "$localBranches"; echo "$remoteBranches"; echo "$tags") |
  #   fzf -m --ansi \
  #     --preview 'git log --pretty=oneline --abbrev-commit --color=always `echo {} | cut -f2` | head -'$LINES |
  #   awk '{print $2}' |
  #   xargs echo
  # )

  # Get current branches from worktrees (so we don't miss newly created ones)
  local current_branches=$(git worktree list --porcelain | awk '/^branch / {sub(/^refs\/heads\//, "", $2); print $2}')

  # Collect checkout history from all worktrees using git reflog (formatted output,
  # already in reverse chronological order, reliable field positions)
  local reflog_branches=""

  # Get worktree paths
  local worktree_paths=$(git worktree list --porcelain | awk '/^worktree / {print substr($0, 10)}')
  while IFS= read -r wt_path; do
    [[ -z "$wt_path" ]] && continue
    local wt_branches=$(
      git -C "$wt_path" reflog HEAD 2>/dev/null |
      grep 'checkout: moving from' |
      cut -d' ' -f 8 |
      grep -v -E '^HEAD|^[0-9a-f]{7,}$'
    )
    if [[ -n "$wt_branches" ]]; then
      reflog_branches+="$wt_branches"$'\n'
    fi
  done <<< "$worktree_paths"

  # Combine current branches (at top) with reflog branches, remove duplicates
  result=$(
    (echo "$current_branches"; echo "$reflog_branches") |
    grep -v '^$' |
    awk '!seen[$0]++' |
    fzf --tiebreak=index -m --ansi \
      --preview 'git log -$LINES --pretty=oneline --abbrev-commit --color=always {}'
  )

  echo $result
}

fco() {
  local target=$(fzf_get_ref)

  if [[ -z "$target" ]]; then
    return 0;
  fi

  echo git checkout "${target}"
  git checkout "${target}"
}

fzf_ref_widget() {
  local refs=$(fzf_get_ref)
  LBUFFER="${LBUFFER}${refs}"
  local ret=$?
  zle redisplay
  typeset -f zle-line-init >/dev/null && zle zle-line-init
  return $ret
}

zle -N fzf_ref_widget
bindkey '^B' fzf_ref_widget

# CTRL-G - Get git commit
fzf-git-widget() {
  setopt localoptions pipefail 2> /dev/null
  local commits=$(
    git log --pretty=oneline --abbrev-commit --color=always |
    fzf -m --ansi --preview 'git show --color=always `echo {} | cut -d" " -f1` | head -$LINES' |
    awk -F' ' '{print $1}' |
    xargs echo
  )

  if [[ -z "$commits" ]]; then
    zle redisplay
    return 0
  fi

  LBUFFER="${LBUFFER}${commits}"
  local ret=$?
  zle redisplay
  typeset -f zle-line-init >/dev/null && zle zle-line-init
  return $ret
}

zle -N fzf-git-widget
bindkey '^G' fzf-git-widget

fzf-git-status-widget() {
  setopt localoptions pipefail 2> /dev/null
  local files=$(
    git status -s |
    sed 's/^...//' |
    fzf -m --ansi --preview='~/bin/status-preview.sh {}' |
    tr '\n' ' '
  )

  if [[ -z "$files" ]]; then
    zle redisplay
    return 0
  fi

  LBUFFER="${LBUFFER}${files}"
  local ret=$?
  zle redisplay
  typeset -f zle-line-init >/dev/null && zle zle-line-init
  return $ret
}

zle -N fzf-git-status-widget
bindkey '^S' fzf-git-status-widget
