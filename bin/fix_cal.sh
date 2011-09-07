#!/bin/zsh

ratpoison -c "fselect 5"
ratpoison -c "select -"
ratpoison -c "fselect 9"
ratpoison -c "select -"

move_window_to_frame.pl --number 6 --title 'Gmail' --name 'Gmail' --frame 9
move_window_to_frame.pl --number 5 --title 'Calendar' --name 'Calend(e|a)r|Inbox|Exchange' --frame 5
