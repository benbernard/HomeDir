# Sets: ENV_IMPROVEMENT_ROOT, ZSH_VERSION

if [[ "$NINJA_SEARCH_SHELL" = "YES" ]]
then
  AUTO_TITLE_SCREENS=NO
  PS1=
  PROMPT=
  RPROMPT=
fi

if [[ -n "$TITLE" ]]
then
  AUTO_TITLE_SCREENS=NO

  if [[ "$TERM" == "screen" ]]; then
    echo -ne "\ek$TITLE\e\\"
  fi
  if [[ "$TERM" == "xterm" ]]; then
    echo -ne "\e]0;$TITLE\a"
  fi
fi

#Will get the zsh_version from eihooks
ENV_IMPROVEMENT_ZSHRC=$HOME/.eihooks/dotfiles/zshrc

# Fix when setenv isn't available, should probably just move to export at some
# point.
setenv() {
  export $1=$2
}

foreach i (`ls -1 ~/.zshrc.d`) {
  source ~/.zshrc.d/$i
}

if [[ -z $ZSH_VERSION ]] 
then
  ZSH_VERSION=`$SHELL --version | /usr/bin/cut -d ' ' -f 2`
fi

#Setup completion functions
#FPATH=/usr/local/share/zsh/4.2.0/functions
fpath=(~/.zshfuncs $fpath)
autoload -U ~/.zshfuncs/*(:t)

# Add setup for Recs and GitScripts
export PATH=$PATH:$HOME/RecordStream/bin:$HOME/GitScripts/bin
export PERL5LIB=~/RecordStream/lib

#watch for logins
watch=(notme root)

#Do not use the envImprovement SCREENRC, as I want my own rc file
unset SCREENRC

# Fix backspace ... sigh...
stty erase 

# Setup for ninja-search shell
if [[ "$NINJA_SEARCH_SHELL" = "YES" ]]
then
  # if we want screen titling stuff, we'll need to grab that from the
  # envImprovement zshrc, but I don't care enough for the ninja-search shell
  precmd () {
    # Need nasty backgrounding process in order to prevent a rogue % from messing up the prompt
    sh -c "screen -X stuff 'ns '" &!
  }

  preexec () { }

  RPROMPT=
  PROMPT=
  
  HISTFILE=~/.history.ninja-search
fi
