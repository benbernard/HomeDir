#Increase History size
HISTSIZE=400000
SAVEHIST=410000
HISTFILE=${HOME}/.history

setopt INC_APPEND_HISTORY  # immediatly insert history into history file
setopt SHARE_HISTORY       # share history between all shells...don't know if this is a good idea or not... oh it is...
setopt HIST_IGNORE_DUPS    # don't insert immediately duplicated lines twice
setopt HIST_IGNORE_SPACE   # Don't save commands that start with a space to history

# This doesn't work, not sure why
# HISTORY_IGNORE="(^ls *$|^pwd$)"

# # This hook prevents things matching HISTORY_IGNORE from getting into local
# # memory history as well as the file
# # Taken from `man zshall`
# zshaddhistory() {
#   emulate -L zsh
#   ## uncomment if HISTORY_IGNORE
#   ## should use EXTENDED_GLOB syntax
#   # setopt extendedglob
#   [[ ! ($1 =~ ${HISTORY_IGNORE}) ]]

#   local RESULT=$?
#   echo $RESULT
#   return $RESULT
# }
