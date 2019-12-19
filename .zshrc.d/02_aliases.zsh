#Aliases
alias 'xclock=xclock -update 5 -strftime '%a %b %e %l:%M:%S %P' -d -norender'
alias 'rpp=recs toprettyprint --one'
alias 'rtt=recs totable'
alias 'ns=ninjaWarpSearch'

#ls alias, mainly add --color
alias 'ls=/bin/ls -G'
alias 'lt=/bin/ls -G -latr'

#zmv stuff
autoload zmv
alias 'zcp=noglob zmv -C -W'
alias 'zln=noglob zmv -L -W'
alias 'zmv=noglob zmv -M -W'

#Set screen to content to already running session autmatically
alias 'screen=screen -x -RR'

# Reasonable bc defaults, like scale > 0:
alias 'bc=bc -l'

#Alias to start xchat in the background for irc
if [[ -e /usr/bin/xchat ]]
then
  alias 'irc=xchat &'
fi

# p aliases to popd a directory
alias 'p=popd'

# Add --prompt to s3_upload.pl
alias 's3_upload.pl=s3_upload.pl --prompt'

# Prompt when about to overwrite a file with mv (use -f to force)
alias 'mv=mv -i'

# If hub is installed alias git to it
if type hub >/dev/null;
then
  alias 'git=hub'
fi

# Use gcal instead of useless cal
alias cal=gcal
alias cal3='gcal .'

# Fucking coreutils getting mapped as gutil...
alias realpath=grealpath

# Vim aliases
# Use neovim... really?
alias vim=nvim
alias 'viminit=vim ~/.config/nvim/init.vim'
alias 'cleanvim=vim -u NONE'
alias 'sudovim=sudo vim -u NONE --noplugin'
alias 'vimchanged=vim `git s`'

alias 'longtail=tail -n 1000 -f'

alias 'gcm=git commit -m '

# Add alias for sublime merge
alias smerge="/Applications/Sublime\ Merge.app/Contents/MacOS/sublime_merge &!"

# Make run-help / help work
autoload -Uz run-help
autoload -Uz run-help-git
autoload -Uz run-help-svn
autoload -Uz run-help-svk
unalias run-help
alias help=run-help

alias od=onedrivecmd

alias 'rspecf=bin/rspec --fail-fast'

# Fix HEAD^ in shell commands
# setopt NO_EXTENDED_GLOB
alias 'git=noglob hub'

# Docker bullshit
alias 'da=docker attach --sig-proxy=false'
