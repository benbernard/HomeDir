#!/usr/local/bin/zsh

tmux display-message -p '#S' | grep server 1>/dev/null

if [ "$?" != 0 ];
then
  echo "Run inside a server tmux!"
  exit 1;
fi

tmux set-option -t server allow-rename off

# This is total jank, but gets what I want done
tmux rename-window web

tmux new-window -n worker
tmux new-window -n watch
tmux new-window -n inspector
tmux new-window -n paste-tracker
tmux new-window -n genghis
tmux new-window -n autossh

tmux send-keys -t web "cdcl; foreman start web" Enter
tmux send-keys -t worker "cdcl; foreman start worker" Enter
tmux send-keys -t watch "cdcl; while (1) { grunt min-watch }" Enter
tmux send-keys -t inspector "cdcl; node-inspector" Enter
tmux send-keys -t paste-tracker "cd; cd bin/mac; ./paste-tracker.pl" Enter
tmux send-keys -t genghis "cd; genghisapp -L -F" Enter
tmux send-keys -t autossh "AUTOSSH_POLL=30 AUTOSSH_DEBUG=1 autossh -M2000 -L6667:localhost:6667 -N cmyers.org" Enter
