#!/bin/zsh

ratpoison -c "fselect 0"
sleep 1;

# This should've already been done...
# /usr/local/bin/ratpoison -c "title main shell"
# /usr/local/bin/ratpoison -c "number 0"

# First clear all frames
clear_frames.pl
#perl -e 'print "type\n"; getc';

# Now name and number all the windows we've made above... hopefully firefoxes have started
move_window_to_frame.pl --number 0 --exactTitle 'main shell' --frame 0
#perl -e 'print "type\n"; getc';
move_window_to_frame.pl --number 1 --title 'Chrome main' --name 'Youtube' --frame 2
#perl -e 'print "type\n"; getc';
move_window_to_frame.pl --number 2 --exactTitle 'irc' --frame 10
#perl -e 'print "type\n"; getc';
move_window_to_frame.pl --number 4 --exactTitle 'biffBuff' --frame 3
#perl -e 'print "type\n"; getc';

#Removed until I can get both windows open at once.
#move_window_to_frame.pl --number 6 --exactTitle 'Calendar' --frame 5

move_window_to_frame.pl --number 7 --exactTitle 'Ninja Search' --frame 12
#perl -e 'print "type\n"; getc';
move_window_to_frame.pl --number 8 --exactTitle 'Window List' --frame 8
#perl -e 'print "type\n"; getc';
move_window_to_frame.pl --number 9 --exactTitle 'Buffers' --frame 4
#perl -e 'print "type\n"; getc';
move_window_to_frame.pl --number 10 --exactTitle 'Top' --frame 7 
#perl -e 'print "type\n"; getc';
move_window_to_frame.pl --number 11 --exactTitle 'bc' --frame 11
#perl -e 'print "type\n"; getc';
move_window_to_frame.pl --number 13 --exactTitle 'xclock' --frame 9
#perl -e 'print "type\n"; getc';
move_window_to_frame.pl --number 3 --title 'Gmail' --name 'Gmail|Mail' --frame 1
#perl -e 'print "type\n"; getc';
#move_window_to_frame.pl --number 12 --exactTitle 'main shell' --frame -
#sleep 1;
#move_window_to_frame.pl --number 15 --title minishell --name 'minishell' --frame 12
#move_window_to_frame.pl --number 16 --title 'FatalMonitor' --name 'SC Fatal Dashboard' --frame 4


ratpoison -c "fselect 0"
