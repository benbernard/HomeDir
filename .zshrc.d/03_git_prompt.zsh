## http://www.jonmaddox.com/2008/03/13/show-your-git-branch-name-in-your-prompt/
#function git_current_branch () {
#  git branch --no-color 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/\1/'
#}
#
## git status with a dirty flag
#function git_status_flag () {
#  git_status="$(git status 2>/dev/null)"
#  remote_pattern="# Your branch is .* by .* commit"
#  diverge_pattern="# Your branch and .* have diverged"
#
#  if [[ ${git_status} =~ "working directory clean" ]]; then
#    state=""
#  else
#    state="*"
#  fi
#
#  if [[ ${git_status} =~ ${remote_pattern} ]]; then
#    if [[ ${git_status} =~ "ahead" ]]; then
#      remote="↑"
#    else
#      remote="↓"
#    fi
#  fi
#
#  if [[ ${git_status} =~ ${diverge_pattern} ]]; then
#    remote="↕"
#  fi
#
#  echo "${state}${remote}"
#}
#
#function git_prompt_decorations () {
#    local branch=`git_current_branch`
#    local git_status=`git_status_flag`
#    if [[ ! -z $branch ]]; then
#        echo -en "[${branch}${git_status}] "
#    fi
#}

#preexec () { 
#  # End the colorization of the line
#  echo -n '\e[0m' 
#
#  # Coped from envImprovement zshrc, sets the command as the
#  # screen title
#  if [[ "$TERM" == "screen" ]]; then
#    local CMD=${1/% */}  # kill all text after and including the first space
#    echo -ne "\ek$CMD\e\\"
#  fi
#
#  #git_branch=`git_prompt_decorations`
#  #PS1="$git_branch$MY_PROMPT"
#}

#These lines are supposed to initialize the SC info for the prompt, but don't
#seem to be working
#autoload -Uz vcs_info
#autoload -Uz vcs_info_printsys

