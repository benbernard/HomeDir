#!/usr/bin/zsh

while (`/bin/true`) {
  inotifywait -e close_write /tmp/screen-exchange
  DISPLAY=:0 xclip -i < /tmp/screen-exchange
}
