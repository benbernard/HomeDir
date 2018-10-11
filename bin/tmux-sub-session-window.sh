#!/usr/local/bin/zsh

SESSION=$1
TARGET_WINDOW=$2
MINI_SESSION="mini-${1}-$TARGET_WINDOW"

echo $SESSION $MINI_SESSION $TARGET_WINDOW

if ! tmux has-session -t=$MINI_SESSION; then
  tmux new-session -d -t $SESSION -s $MINI_SESSION
fi

if tmux list-windows -t $SESSION | grep -E '^\d+: '${TARGET_WINDOW}'\b' 1>/dev/null; then
  tmux select-window -t ${MINI_SESSION}:${TARGET_WINDOW}
fi

tmux attach-session -t $MINI_SESSION
