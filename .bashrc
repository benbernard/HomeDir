# Added by ForgeCode installer
export PATH="/Users/benbernard/.local/bin:$PATH"
[ -f ~/.fzf.bash ] && source ~/.fzf.bash

source <(bento completion bash)

[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh
eval "$(atuin init bash)"

# >>> gohan setup, do not edit this section <<<
# !! Contents within this block are managed by gohan !!
# gohan setup revision 6
[ -f "/Users/benbernard/.config/gohan/gohan.sh" ] && source "/Users/benbernard/.config/gohan/gohan.sh"
# <<< gohan setup end <<<
