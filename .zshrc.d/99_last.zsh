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

FAST_SYNTAX_PATH=$(submodule fast-syntax-highlighting)/fast-syntax-highlighting.plugin.zsh
if [[ -e ${FAST_SYNTAX_PATH} ]]; then
  source ${FAST_SYNTAX_PATH}
fi
