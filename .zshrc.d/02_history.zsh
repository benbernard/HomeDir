#Increase History size
HISTSIZE=400000
SAVEHIST=410000
HISTFILE=${HOME}/.history

setopt INC_APPEND_HISTORY # immediatly insert history into history file
setopt SHARE_HISTORY      # share history between all shells...don't know if this is a good idea or not... oh it is...
setopt HIST_IGNORE_DUPS   # don't insert immediately duplicated lines twice
