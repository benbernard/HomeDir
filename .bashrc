# Added by ForgeCode installer
export PATH="/Users/benbernard/.local/bin:$PATH"
[ -f ~/.fzf.bash ] && source ~/.fzf.bash

source <(bento completion bash)

[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh
eval "$(atuin init bash)"
