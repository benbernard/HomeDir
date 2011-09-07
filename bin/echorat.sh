#!/bin/zsh

/usr/local/bin/ratmen -t echo "$1" 1 -p &
sleep $2
kill %1
