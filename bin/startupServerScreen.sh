#!/usr/local/bin/zsh

# This is total jank, but gets what I want done

screen
screen
screen
screen

screen -p 0 -X stuff "foreman start"
screen -p 1 -X stuff "grunt observe"
screen -p 2 -X stuff "node-inspector"
screen -p 3 -X stuff "java -jar /Users/bernard/bin/selenium-server-standalone-2.38.0.jar"
screen -p 4 -X stuff "cd; cd bin/mac; ./paste-tracker.pl"
