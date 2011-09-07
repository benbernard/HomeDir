#Aliases
alias 'xclock=xclock -update 5 -strftime '%a %b %e %l:%M:%S %P' -d -norender'
alias 'rpp=recs-toprettyprint --one'
alias 'rtt=recs-totable'
alias 'ns=ninjaWarpSearch'

#ls alias, mainly add --color
alias 'ls=ls --color=auto'
alias 'la=ls --color=auto -A'
alias 'lt=ls --color=auto -latr'
alias 'lc=ls --color=never'

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
