# Completion for claude-session-picker command
_claude_session_picker() {
  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-r --resume)'{-r,--resume}'[Automatically resume the selected session]' \
    '--debug[Debug mode: process only one session and show curl command]' \
    '--only[Only consider the specified session file]:session file:_claude_session_picker_files' \
    '--preview[Print preview for --only file and exit (requires --only)]' \
    '(-h --help)'{-h,--help}'[Show help message]'
}

# Helper function to complete session files from ~/.claude/projects
_claude_session_picker_files() {
  local -a session_files
  local claude_projects_dir="${HOME}/.claude/projects"

  if [[ -d "$claude_projects_dir" ]]; then
    # Find all .jsonl files in the projects directory
    session_files=(${(f)"$(find "$claude_projects_dir" -name "*.jsonl" -type f 2>/dev/null)"})
    _describe 'session file' session_files
  fi
}

compdef _claude_session_picker claude-session-picker
