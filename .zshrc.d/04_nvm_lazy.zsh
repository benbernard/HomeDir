# Lazy load nvm - only loads when you first use node/npm/etc
# This saves 1-2 seconds on shell startup
#
# Trade-off: First node/npm command in a new shell has ~1s delay

lazy_load_nvm() {
  unset -f node npm npx nvm pnpm yarn
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  # Skip bash_completion - it tries to run compinit again which causes conflicts
  # [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
  # Enable corepack to make yarn/pnpm available
  command -v corepack >/dev/null 2>&1 && corepack enable 2>/dev/null
}

# Create wrapper functions that lazy-load nvm on first use
for cmd in node npm npx nvm pnpm yarn; do
  eval "$cmd() { lazy_load_nvm && $cmd \"\$@\" }"
done
