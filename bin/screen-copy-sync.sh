#!/usr/bin/zsh

bkill -9 --pattern '^/usr/bin/zsh .*screen-copy-sync.sh' --except $$

while (`/bin/true`) {
  inotifywait -e close_write /tmp/screen-exchange
  DISPLAY=:0 xclip -i </tmp/screen-exchange &
}
