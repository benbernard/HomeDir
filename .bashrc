# Added by ForgeCode installer
export PATH="/Users/benbernard/.local/bin:$PATH"
[ -f ~/.fzf.bash ] && source ~/.fzf.bash

[[ -f ~/.bash-preexec.sh ]] && source ~/.bash-preexec.sh
eval "$(atuin init bash)"

# Job-specific bash setup lives in the private site repo, not this public repo.
[ -f "$HOME/site/site.bash" ] && source "$HOME/site/site.bash"

# Homebrew Go auto-detects GOROOT; drop a stale exported value.
if [ -n "${GOROOT:-}" ] && [ ! -d "$GOROOT" ]; then unset GOROOT; fi
