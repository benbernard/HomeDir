BREW_CMD=/opt/homebrew/bin/brew
if [[ -e $BREW_CMD ]]; then
    eval "$(${BREW_CMD} shellenv)"
fi
