# ZDOTDIR=/

# Job-specific environment setup lives in the private site repo, not this public repo.
[[ -f "$HOME/site/site.env.zsh" ]] && source "$HOME/site/site.env.zsh"

# Homebrew's Go auto-detects GOROOT. Clear a stale exported value (for example
# one inherited from an app launched before a Go upgrade) so `go` works without
# needing `env -u GOROOT`.
if [[ -n "${GOROOT:-}" && ! -d "$GOROOT" ]]; then
  unset GOROOT
fi
