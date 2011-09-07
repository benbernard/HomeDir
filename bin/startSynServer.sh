#!/bin/sh

# First kill all the old processes
killall synergys

/usr/bin/synergys --config ~/synergy/synergy.conf 
