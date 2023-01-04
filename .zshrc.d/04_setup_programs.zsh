# Do a bunch of tricks to make nvm faster.  Only source once we need it.
# Directly setup PATH up so I don't have to default source it (its slow)
export NVM_DIR="$HOME/.nvm"

nvm() {
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
  nvm "$@"
}

# export PATH=$PATH:~/.nvm/versions/node/v6.9.5/bin
