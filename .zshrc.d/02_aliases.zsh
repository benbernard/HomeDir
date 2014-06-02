#Aliases
alias 'xclock=xclock -update 5 -strftime '%a %b %e %l:%M:%S %P' -d -norender'
alias 'rpp=recs-toprettyprint --one'
alias 'rtt=recs-totable'
alias 'ns=ninjaWarpSearch'

#ls alias, mainly add --color
alias 'ls=/bin/ls -G'
alias 'la=/bin/ls -G -A'
alias 'lt=/bin/ls -G -latr'
alias 'lc=/bin/ls --color=never'

#zmv stuff
autoload zmv
alias 'zcp=noglob zmv -C -W'
alias 'zln=noglob zmv -L -W'
alias 'zmv=noglob zmv -M -W'

#A couple of u alias... but please remember u NUM
alias 'uu=cd ../..'
alias 'uuu=cd ../../..'

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

# Prompt when about to overwrite a file iwht mv (use -f to force)
alias 'mv=mv -i'

# If hub is installed alias git to it
if type hub >/dev/null;
then
  alias 'git=hub'
fi
