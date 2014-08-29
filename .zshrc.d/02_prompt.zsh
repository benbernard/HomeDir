#key bindings for command line editing (man zshzle)
#Get back emacs search commands
bindkey "^R" history-incremental-search-backward
bindkey "^S" history-incremental-search-forward

#AWESOME...
#pushes current command on command stack
#and gives blank line, after that line runes
#command stack is popped
bindkey "^t" push-line-or-edit

#Map ctrl-u and ctrl-k to be like emacs mode
bindkey "^U" kill-whole-line
bindkey "^K" kill-line

# helps debug completion problems, F2
bindkey "^[OQ" _complete_debug

# make backspace work in vi-insert mode
bindkey -v  backward-delete-char
bindkey -v  backward-delete-char

# bind v in vi command mode to open current command in the $EDITOR
autoload edit-command-line
zle -N edit-command-line

# bind v in vi cmd mode to edit the current command in vim
bindkey -M vicmd v edit-command-line
setopt AUTO_CD    #if you type in a directory and hit enter, cd there
setopt AUTO_PUSHD #cd pushes directories on to the stack

#Setting to fix bad settings in global zshrc
#Do not autocorrect on enter, I don't like that much correction
setopt NO_CORRECT_ALL

#Report 'time' on things that took longer than 10 seconds
REPORTTIME=10

#Prompt
# the cool thing about these prompt settings is that they make your command line
# entries appear blue, but everything else stays the same.  Zany!
# 
# Also switches between blue and red depending on the exit code of the last command.

# auto-quote special shell characters as you type a URL, so that you don't have
# to single quote it
#
# we have to jump through some hoops here in case this isn't found
unfunction url-quote-magic >& /dev/null
if autoload +X url-quote-magic 2> /dev/null; then
  # we successfully loaded the url-quote-magic function
  zle -N self-insert url-quote-magic
fi

# This prompt uses oh-my-zsh prompt stuff for colors and the git prompt so lets deconstruct this:
# Really useful reference for the prompt: http://www.nparikh.org/unix/prompt.php
#
# Note: using $fg_bold[color] inside a %(x.true.false) statment yields prompts
# with lines longer than the width of the terminal
#
# %(0?.%{\e[1;32m%}.%{\e[3;31m%})
#   First, lets color the first section of the prompt on the command exit of the
#   previous command %(x.true.false) is the syntax and x=? means the exit code of
#   the previous command
#   The \e[1;32m codes are colors.  1 for bold 32 or 31 for green/red (1 vs 3
#   for foreground vs. background)
# ➜
#   Literal character, unicode.
# %*
#   Current time.  For some reason p, P, Y all don't work.  zsh seems to have
#   some alternatives that do work
# %{$reset_color%}
#   Reset the possible color from the previous command check
# %(4L.S:$SHLVL .)
#   Check the current SHLVL, if it is greater than 3 display S:$SHLVL so I can
#   know if I'm in a sub shell
# %{$fg_bold[blue]%}$(site_prompt_info)%{$fg_bold[blue]%}
#   Color the prompt blue, display the site (machine) specific portion of the
#   prompt with the call to site_prompt_info (which will be defined by
#   99_last.zsh if nowhere else
# $(vi_mode_prompt_info)
#   Only set when in zle command line mode see .oh-my-zsh/plugins/vi-mode for
#   more info, displays $MODE_INDICATOR when in command mode in the prompt
# %%
#   Literal character: %
# %{$reset_color%}'
#   Not sure what this does, but it was in the example.
PROMPT=$'%(0?.%{\e[1;32m%}.%{\e[3;31m%})➜ %*%{$reset_color%} %(4L.S:$SHLVL .)%{$fg_bold[blue]%}$(git_prompt_info_site)%{$reset_color%}$(vi_mode_prompt_info) %%%{$reset_color%} '

setopt TRANSIENT_RPROMPT # RPROMPT disappears in terminal history great for copying
#RPROMPT="%{${fg[$PROMPT_COLOR]}%}%B%(7~,.../,)%6~%b%{${fg[default]}%} $(vi_mode_prompt_info)"

# Remove a space
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[blue]%})%{$fg[yellow]%}✗%{$reset_color%}"

#change branch name to yellow, not red
ZSH_THEME_GIT_PROMPT_PREFIX="g:(%{$fg[yellow]%}"

ZSH_THEME_GIT_PROMPT_SUFFIX="%{$fg_bold[blue]%})"

# change final % in prompt into red if in command mode
MODE_INDICATOR="%{$fg_bold[red]%}"

# get the name of the branch we are on
function git_prompt_info_site() {
  echo "$ZSH_THEME_GIT_PROMPT_PREFIX$(gitbranch)$ZSH_THEME_GIT_PROMPT_SUFFIX"
}
