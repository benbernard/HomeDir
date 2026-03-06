# fnm (Fast Node Manager) - fast, no lazy loading needed
# --use-on-cd: auto-switch node version when cd'ing into dirs with .nvmrc/.node-version
# --version-file-strategy=recursive: looks up parent dirs for .node-version/.nvmrc
# --log-level=quiet: suppress output
eval "$(fnm env --use-on-cd --version-file-strategy=recursive --log-level=quiet)"
