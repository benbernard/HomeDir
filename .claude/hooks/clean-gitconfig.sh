#!/bin/bash
# Deduplicate safe.directory = /var/app in global gitconfig.
# Uses git's own config commands so we don't have to parse the file ourselves.

# Remove all safe.directory entries matching /var/app
git config --global --unset-all safe.directory '^/var/app$' 2>/dev/null

# Add back exactly one
git config --global --add safe.directory /var/app
