# Leak Protection Before Committing

`~` is a **public** repository. Tracked dotfiles, `.config`, and shell startup
files are world-readable and archived by third parties. Treat everything
committed here as permanently public.

The authoritative, up-to-date policy and the enforcing scripts live outside this
public repo, in the private `~/site` checkout:

- **Pre-commit checklist and policy:** `~/site/docs/homedir-publishing-guard.md`
- **Files intentionally kept dirty:** `~/site/docs/homedir-kept-dirty.md`
- **Enforcing hook (internal-token scan):** `~/site/.githooks/homedir/pre-commit`
- **Local ignore list:** `~/site/homedir-exclude`
- **Installer:** `~/site/bin/install-homedir-guard.sh`

Before committing:

1. `cd ~ && git status` and review what is staged.
2. Let the pre-commit hook run; do not use `--no-verify`. If it blocks, move the
   content into `~/site` or genericize it.
3. Some tracked dotfiles carry internal-tool blocks that keep them permanently
   dirty. Stage around them with `git add -p`; never `git add -A` from `~`. See
   `~/site/docs/homedir-kept-dirty.md`.
4. If `~/site` is unavailable, keep changes to generic, publishable content
   only: no credentials, no internal hostnames, service names, or tool names,
   and no personal email addresses or internal links.

Never commit real secrets (keys, tokens, cookies, private keys) regardless of
tooling; see `docs/development-workflows.md` for the general secret rules.
