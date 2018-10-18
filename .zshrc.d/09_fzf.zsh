# Inspired by
# - https://github.com/junegunn/fzf/wiki/Examples#git
# - https://junegunn.kr/2016/07/fzf-git/

# fco - checkout git branch/tag
fzf_get_ref() {
  local tags branches target

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

  # Instead of getting at the branches, remote branches, and tags, just get the
  # list of things we've checked out to HEAD recently

  result=$(
    git reflog HEAD |
    grep -E '^\S+ HEAD@{\d+}: checkout: moving from' |
    cut -d' ' -f 8 |
    awk '!seen[$0] {print} {++seen[$0]}' |
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
