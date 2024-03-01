[ -f ~/.fzf.bash ] && source ~/.fzf.bash

source <(bento completion bash)

[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh
eval "$(atuin init bash)"
