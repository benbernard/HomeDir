#key bindings for command line editing (man zshzle)
#Get back emacs search commands
bindkey "^R" history-incremental-search-backward
bindkey "^S" history-incremental-search-forward

#AWESOME...
#pushes current command on command stack
#and gives blank line, after that line runes
#command stack is popped
bindkey "^Q" push-line-or-edit

#Map ctrl-u and ctrl-k to be like emacs mode
bindkey "^U" kill-whole-line
# Ctrl-k destroys from cursor to front of line
bindkey "^K" backward-kill-line
# bindkey "^K" kill-line

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

# Copy earlier command argument
bindkey "^[." insert-last-word
autoload -Uz copy-earlier-word
zle -N copy-earlier-word
bindkey "^Y" copy-earlier-word

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

# powerlevel10k setup
if [[ -n "$CODEX_SHELL" ]]; then
  setopt PROMPT_SUBST

  _codex_prompt_git() {
    local branch
    branch=$(gitbranch 2>/dev/null)
    [[ -z "$branch" ]] && return
    branch=${branch//\%/%%}
    print -r -- " [$branch]"
  }

  # Codex's built-in shell currently runs best with plain ASCII and
  # light-background colors instead of the regular Powerlevel10k glyph prompt.
  PROMPT=$'%F{240}%n@%m %F{25}%~%f%F{28}$(_codex_prompt_git)%f %(?..%F{124}exit:%?%f)\n%F{22}%#%f '
  RPROMPT=
elif [[ -z "$FORGE_SIMPLE_ZSH" ]]; then
  source $(submodule powerlevel10k)/powerlevel10k.zsh-theme
else
  PROMPT='%n@%m %1~ %# '
  RPROMPT=
fi
# powerlevel10k config is in 03_p10k.zsh

# only use autosuggest if not in VSCODE, not recording, and not in the
# simplified forge shell.
if [[ -z "$FORGE_SIMPLE_ZSH" && ${recording} != "true"  && -z "$VSCODE_IPC_HOOK_CLI" ]]; then
  zmodload zsh/zpty 1>/dev/null 2>/dev/null
  if type zpty >/dev/null;
  then;
    # zsh-autosuggestions setup
    export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
    export ZSH_AUTOSUGGEST_USE_ASYNC=1
    if [[ -n "$CODEX_SHELL" ]]; then
      export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=245'
    fi
    source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
    bindkey '^^' autosuggest-accept # Binds Ctrl-6 to accept suggestion, iterm maps Ctrl-Enter to Ctrl-6 (Send Hex Code -> 0x1E)
    bindkey '\e[27;5;13~' autosuggest-accept # Binds escape code for ctrl+enter in ghostty, also needs support in tmux.conf
  fi
fi
