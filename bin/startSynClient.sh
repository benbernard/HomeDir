#!/bin/sh

# First kill all the old processes
killall synergyc
pkill -f "ssh.* -L 24800:.*:24800"

LAPTOP=`cat /var/tmp/laptopHost`

/usr/bin/ssh -2 -f -N -L 24800:$LAPTOP:24800 $LAPTOP &
disown

DISPLAY=localhost:0.0 /usr/bin/synergyc localhost
