# generate a site_prompt_info function if doesn't already exist

# If the site_prompt_info wasn't defined elsewhere, define one to give the git
# info
type site_prompt_info 1>/dev/null 2>/dev/null

if [[ $? != 0 ]]; then;
  site_prompt_info() {
    ref=`git symbolic-ref HEAD 2>/dev/null`
    if [[ $? != 0 ]]; then;
      echo "%{$fg[red]%}none"
      return
    fi
  }
fi

# This must come last, enables zsh prompt highlighting
if [[ -e $HOME/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source $HOME/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

if [[ -e $HOME/zaw ]]; then
  source $HOME/zaw/zaw.zsh
  bindkey '^O' zaw
fi
