# Setup fzf
# ---------
if [[ ! "$PATH" == */Users/bernard/.local/share/nvim/plugged/fzf/bin* ]]; then
  export PATH="$PATH:/Users/bernard/.local/share/nvim/plugged/fzf/bin"
fi

# Auto-completion
# ---------------
[[ $- == *i* ]] && source "/Users/bernard/.local/share/nvim/plugged/fzf/shell/completion.zsh" 2> /dev/null

# Key bindings
# ------------
source "/Users/bernard/.local/share/nvim/plugged/fzf/shell/key-bindings.zsh"

