#!/usr/local/bin/zsh

tmux display-message -p '#S' | grep server 1>/dev/null

if [ "$?" != 0 ];
then
  echo "Run inside a server tmux!"
  exit 1;
fi

# First turn off window rename (need global option because of race conditions
# with shell re-titling)
tmux set-option -g allow-rename off

# Setup windows, note we rename the current window instead of making all new
tmux rename-window web

tmux new-window -n worker
tmux new-window -n valueCleaner
tmux new-window -n watch
tmux new-window -n paste-tracker
tmux new-window -n autossh

# Turn off rename on windows so that when we unset the global option it will be
# set off on the windows
tmux set-window-option -t web allow-rename off
tmux set-window-option -t worker allow-rename off
tmux set-window-option -t valueCleaner allow-rename off
tmux set-window-option -t watch allow-rename off
tmux set-window-option -t paste-tracker allow-rename off
tmux set-window-option -t autossh allow-rename off

# Startup server commands.  Use send-keys so I can flip to windows and
# control-c from programs and get into a shell
tmux send-keys -t web "cdcl; foreman start web" Enter
tmux send-keys -t worker "cdcl; foreman start worker" Enter
tmux send-keys -t valueCleaner "cdcl; foreman start pgBridge valueCleaner" Enter
tmux send-keys -t watch "cdcl; while (1) { grunt min-watch }" Enter
tmux send-keys -t paste-tracker "cd; cd bin/mac; ./paste-tracker.pl" Enter
tmux send-keys -t autossh "AUTOSSH_POLL=30 AUTOSSH_DEBUG=1 autossh -M2000 -L6667:localhost:6667 -N cmyers.org" Enter

# Turn back on global window renames
tmux set-option -g allow-rename on
