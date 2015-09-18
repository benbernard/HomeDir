#Do not use the envImprovement SCREENRC, as I want my own rc file
unset SCREENRC

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
