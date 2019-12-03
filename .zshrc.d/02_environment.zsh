#Environment
setenv EDITOR nvim
setenv VISUAL nvim
setenv PAGER less
setenv SCREENDIR ~/.screen         # directory to put screen sockets
setenv URLOPENER_LOG_FILE $HOME/.urlopener.log # Have the url opener log
setenv LS_COLORS 'no=00:fi=00:di=01;34:ln=01;31:pi=40;33:so=01;35:do=01;35:bd=40;33;01:cd=40;33;01:or=40;31;01:ex=01;32:*.tar=01;31:*.tgz=01;31:*.arj=01;31:*.taz=01;31:*.lzh=01;31:*.zip=01;31:*.z=01;31:*.Z=01;31:*.gz=01;31:*.bz2=01;31:*.deb=01;31:*.rpm=01;31:*.jar=01;31:*.jpg=01;35:*.jpeg=01;35:*.gif=01;35:*.bmp=01;35:*.pbm=01;35:*.pgm=01;35:*.ppm=01;35:*.tga=01;35:*.xbm=01;35:*.xpm=01;35:*.tif=01;35:*.tiff=01;35:*.png=01;35:*.mpg=01;35:*.mpeg=01;35:*.avi=01;35:*.fli=01;35:*.gl=01;35:*.dl=01;35:*.xcf=01;35:*.xwd=01;35:*.ogg=01;35:*.mp3=01;35:*.wav=01;35:*.tex=01;33:*.sxw=01;33:*.sxc=01;33:*.lyx=01;33:*.pdf=0;35:*.ps=00;36:*.asm=1;33:*.S=0;33:*.s=0;33:*.h=0;31:*.c=0;35:*.cxx=0;35:*.cc=0;35:*.C=0;35:*.o=1;30:*.am=1;33:*.py=0;34:'

# Display terminal colors and ignore case in search in less
setenv LESS '-i -R'

# Setup GOPATH so that 'go get' and things can work
export GOPATH="$HOME/gocode"

path=(
  /usr/local/bin # Local bin ahead of path so it can override
  $PATH
  $HOME/bin
  /usr/local/symlinks
  /usr/local/scripts
  /usr/local/buildtools/java/jdk/bin
  /usr/local/sbin
  /usr/local/bin
  /usr/sbin
  /usr/bin
  /sbin
  /bin
  $HOME/RecordStream/bin
  $HOME/GitScripts/bin
  $GOPATH/bin
  $HOME/bin/python-install/bin
)

export VIM_TEMP="/var/tmp/$USER/vim-temp"

# used to have gnu utils override mac utils, but causing problmes on shell startup (ls error)
# export PATH=/usr/local/bin:/usr/local/opt/coreutils/libexec/gnubin:$PATH:$HOME/bin
# export MANPATH="/usr/local/opt/coreutils/libexec/gnuman:$MANPATH"

if [[ ! -d $VIM_TEMP ]]; then
  mkdir -p $VIM_TEMP
fi

ulimit -n 10240 1>/dev/null 2>/dev/null # More file descriptors for the stingy mac, helps with grunt watch

# Add setup for Recs and GitScripts
export PERL5LIB=~/RecordStream/lib

#watch for logins who are not me
watch=(notme root)

# Fix backspace ... sigh...
# stty erase 

# These were added to make local perl libs a thing, probably added by a program
export PERL_LOCAL_LIB_ROOT="/Users/bernard/perl5:$PERL_LOCAL_LIB_ROOT";
export PERL_MB_OPT="--install_base "/Users/bernard/perl5"";
export PERL_MM_OPT="INSTALL_BASE=/Users/bernard/perl5";
export PERL5LIB="/Users/bernard/perl5/lib/perl5:$PERL5LIB";
export PATH="/Users/bernard/perl5/bin:$PATH";

### Added by the Heroku Toolbelt
export PATH="/usr/local/heroku/bin:$PATH"

# Setup fzf
# Use ag for searching (uses .agignore)
export FZF_DEFAULT_COMMAND='rg --hidden --files'
export FZF_CTRL_T_COMMAND='rg --hidden --files'

# Default display options (taken from readme)
export FZF_DEFAULT_OPTS='--height 40% --reverse --border -i -m --bind ctrl-A:select-all,ctrl-d:deselect-all'

# Setup set -x "prompt" for logging commands
#   %1N - Script name (with only last path component)
#   %i - The current line number
#   %* - The time with seconds
# Example:
#   title:2+11:22:04 > setopt prompt_subst
export PS4='%1N:%i+%* > '


export PYTHONUSERBASE=$HOME/bin/python-install
