#!/bin/zsh

# Thin wrapper for backward compatibility.
# The real logic is in ~/bin/meeting-notify (compiled TypeScript binary).
# MeetingBar now calls meeting-notify directly via eventStartScript.scpt,
# but this wrapper exists for any manual scripts that call event-prompt.sh.

# Forward all arguments (including plist paths) to meeting-notify
exec ~/bin/ts/bin/meeting-notify "$@"
