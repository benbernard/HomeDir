# Path to your oh-my-zsh configuration.
ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="robbyrussell"

# Set to this to use case-sensitive completion
# CASE_SENSITIVE="true"

# Comment this out to disable weekly auto-update checks
# DISABLE_AUTO_UPDATE="true"

# Uncomment following line if you want to disable colors in ls
# DISABLE_LS_COLORS="true"

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment following line if you want red dots to be displayed while waiting for completion
COMPLETION_WAITING_DOTS="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Example format: plugins=(rails git textmate ruby lighthouse)
#plugins=(git ruby github nyan python perl vi-mode django)
plugins=(git ruby python perl vi-mode)

source $ZSH/oh-my-zsh.sh

# Customize to your needs...
export PATH=/usr/local/bin:/usr/local/symlinks:/usr/local/scripts:/usr/local/buildtools/java/jdk/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/home/benbernard/bin:/home/benbernard/RecordStream/bin:/home/benbernard/GitScripts/bin:/home/benbernard/bin:/home/benbernard/RecordStream/bin:/home/benbernard/GitScripts/bin

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

foreach i (`ls -1 ~/.zshrc.d/*.zsh`) {
  source $i
}

if [[ -z $ZSH_VERSION ]] 
then
  ZSH_VERSION=`$SHELL --version | /usr/bin/cut -d ' ' -f 2`
fi

#Setup completion functions
#FPATH=/usr/local/share/zsh/4.2.0/functions
if [[ -d ~/.zshfuncs ]]; then
  fpath=(~/.zshfuncs $fpath)
  autoload -U ~/.zshfuncs/*(:t)
fi

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

# Must have this for custom completions
compinit

PATH=$PATH:$HOME/.rvm/bin # Add RVM to PATH for scripting

if [[ -e ~/.zproifle ]]; then
    source ~/.zprofile
fi

export PERL_LOCAL_LIB_ROOT="/Users/bernard/perl5:$PERL_LOCAL_LIB_ROOT";
export PERL_MB_OPT="--install_base "/Users/bernard/perl5"";
export PERL_MM_OPT="INSTALL_BASE=/Users/bernard/perl5";
export PERL5LIB="/Users/bernard/perl5/lib/perl5:$PERL5LIB";
export PATH="/Users/bernard/perl5/bin:$PATH";
