#Aliases
alias 'xclock=xclock -update 5 -strftime '%a %b %e %l:%M:%S %P' -d -norender'
alias 'rpp=recs toprettyprint --one'
alias 'rtt=recs totable'
alias 'ns=ninjaWarpSearch'


# These aliases mess up warp completions, so I'm going to try without them in warp
if [[ "${WARP_IS_LOCAL_SHELL_SESSION}" -ne 1 ]]; then
  #ls alias, mainly add --color
  if [[ $(uname) == "Darwin" ]]; then
    alias 'ls=/bin/ls -G' alias 'lt=/bin/ls -G -latr'
  else
    alias 'ls=/bin/ls --color=auto'
    alias 'lt=/bin/ls --color=auto -latr'
  fi

  # noglob fixes HEAD^ in shell commands
  alias 'git=noglob git'
fi


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

# Use gcal instead of useless cal
alias cal=gcal
alias cal3='gcal .'

# Fucking coreutils getting mapped as gutil...
if type grealpath 2>/dev/null 1>/dev/null; then
  alias realpath=grealpath
fi

# Vim aliases
# Use neovim... really?
if type nvim >/dev/null;
then;
  alias vim=nvim
fi

alias 'viminit=vim ~/.config/nvim/init.vim'
alias 'vimvsinit=vim ~/.config/nvim/vscode-init.vim'
alias 'cleanvim=vim -u NONE'
alias 'sudovim=sudo vim -u NONE --noplugin'
alias 'vimchanged=vim `git s`'

alias 'longtail=tail -n 1000 -f'

alias 'gcm=git commit -m '

# Make run-help / help work
autoload -Uz run-help
autoload -Uz run-help-git
autoload -Uz run-help-svn
autoload -Uz run-help-svk
unalias run-help 2>/dev/null
alias help=run-help

# alias od=onedrivecmd

alias 'rspecf=bin/rspec --fail-fast'

# Git aliases
alias 'gcam=git commit -am'
alias 'gc=git commit'
alias 'gcm=git commit -m'

alias 'gmt=git mergetool'
alias 'grbc=git rebase --continue'

# Docker attach without killing container
# alias 'da=docker attach --sig-proxy=false'

# alias cdrp to cdcl
alias cdcl=cdrp

# Enable nice repl stuff for node
alias 'nr=node --experimental-repl-await --async-stack-traces'


# Copilot
# alias '??=gh copilot suggest -t shell'
# alias '?g=gh copilot suggest -t git'
# alias '?gh=gh copilot suggest -t gh'

alias 'lg=lazygit'

# vitest
alias 'vt=npx vitest --no-watch --bail 1'

#gh
alias 'rw=gh repo view -w'
alias 'prw=gh pr view -w'
