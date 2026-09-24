# Reset Codex Local State

The macOS app may be displayed as **ChatGPT**, but the current merged app stores its local state under `Codex`. The active bundle is `/Applications/ChatGPT.app`, with bundle identifier `com.openai.codex`.

This reset starts the app with a clean local profile and removes local Codex conversations, projects, history, onboarding flags, configuration, and authentication state. It does **not** delete conversations or files stored in the OpenAI account.

## What the reset preserves

The procedure below intentionally preserves:

- Normal Chrome and Safari profiles.
- Codex's `~/.codex/browser` data.
- Installed skills and plugins.
- Git repositories and Codex worktrees.
- Attachments, generated images, visualizations, and dictation recordings.
- Previous reset backups and legacy migration backups.

## Reset procedure

Run this in Terminal. Quit the app first so its app server cannot recreate the files while they are being moved.

```zsh
osascript -e 'tell application "ChatGPT" to quit'
sleep 3

stamp=$(date +%Y%m%d-%H%M%S)
codex_backup="$HOME/.codex-reset-backup-$stamp"
app_backup="$HOME/Library/Application Support/Codex.reset-backup-$stamp"
mkdir -p "$codex_backup" "$app_backup"

# Reset the Electron/Chromium profile owned by the ChatGPT/Codex app.
move_app_path() {
  local path="$1"
  local backup_subdir="$2"
  [[ -e "$path" ]] || return 0
  mkdir -p "$app_backup/$backup_subdir"
  mv "$path" "$app_backup/$backup_subdir/"
}

move_app_path "$HOME/Library/Application Support/Codex" application-support
move_app_path "$HOME/Library/Caches/Codex" caches
move_app_path "$HOME/Library/Preferences/com.openai.codex.plist" preferences
move_app_path "$HOME/Library/HTTPStorages/com.openai.codex.binarycookies" httpstorages

# Reset Codex local history, state, configuration, auth, and onboarding data.
for path in \
  .codex-global-state.json \
  .codex-global-state.json.bak \
  auth.json \
  config.toml \
  external_agent_session_imports.json \
  transcription-history.jsonl \
  history.jsonl \
  session_index.jsonl \
  models_cache.json \
  cloud-config-bundle-cache.json \
  cloud-requirements-cache.json \
  installation_id \
  version.json \
  .personality_migration \
  .sandbox_migration \
  .app-server-state-reconciled-v1 \
  AGENTS.md \
  state_5.sqlite \
  state_5.sqlite-shm \
  state_5.sqlite-wal \
  thread_history_1.sqlite \
  thread_history_1.sqlite-shm \
  thread_history_1.sqlite-wal \
  logs_2.sqlite \
  logs_2.sqlite-shm \
  logs_2.sqlite-wal \
  memories_1.sqlite \
  memories_1.sqlite-shm \
  memories_1.sqlite-wal \
  goals_1.sqlite \
  goals_1.sqlite-shm \
  goals_1.sqlite-wal \
  queue_1.sqlite \
  queue_1.sqlite-shm \
  queue_1.sqlite-wal
 do
  path="$HOME/.codex/$path"
  [[ -e "$path" ]] && mv "$path" "$codex_backup/"
done

# These directories contain local thread rollouts and derived app state.
for path in \
  sessions \
  archived_sessions \
  shell_snapshots \
  memories \
  sqlite \
  thread-writer-locks \
  process_manager \
  ambient-suggestions \
  cache
 do
  path="$HOME/.codex/$path"
  [[ -e "$path" ]] && mv "$path" "$codex_backup/"
done

```
The reset leaves ChatGPT closed. Launch it manually when you are ready.

The `[[ -e ... ]]` checks make the procedure safe when a file was not created by the installed app version. The backup directories are on the same filesystem, so the moves are reversible and do not duplicate the data.

## Verify the reset

After you launch the app, the local thread database should be newly created. A clean database has no rows in `threads`, `projects`, or `project_roots`:

```zsh
sqlite3 "$HOME/.codex/state_5.sqlite" \
  "SELECT 'threads', COUNT(*) FROM threads
   UNION ALL SELECT 'projects', COUNT(*) FROM projects
   UNION ALL SELECT 'project_roots', COUNT(*) FROM project_roots;"
```

Expected result:

```text
threads|0
projects|0
project_roots|0
```

The app may recreate a small `config.toml`, SQLite files, and Chromium caches on startup. Those regenerated files are normal; the important check is that the thread and project counts remain zero.

## If conversations return

A local reset does not remove account-synced conversations. If conversations return after the new local database is empty, they are coming from the logged-in OpenAI account rather than the old Codex files. Deleting cloud conversations is a separate, destructive action.

OpenAI's retention guidance is documented here: [How is data retained in the macOS app?](https://help.openai.com/en/articles/9268871-how-is-data-retained-in-the-macos-app).

## Restore the previous state

Quit ChatGPT, then move the contents of the relevant timestamped backup directory back to their original locations. Restore the Codex backup to `~/.codex/` and the app-profile backup to the corresponding locations under `~/Library/`.
