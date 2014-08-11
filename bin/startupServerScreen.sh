#!/usr/local/bin/zsh

echo $STY | grep server 1>/dev/null

if [ "$?" != 0 ];
then
  echo "Run inside a server screen!"
  exit 1;
fi

# This is total jank, but gets what I want done

screen
screen
screen
screen
screen
screen

screen -p 0 -X stuff "cdcl; foreman start"
screen -p 1 -X stuff "cdcl; grunt observe"
screen -p 2 -X stuff "node-inspector"
screen -p 3 -X stuff "java -jar /Users/bernard/bin/selenium-server-standalone-2.38.0.jar"
screen -p 4 -X stuff "cd; cd bin/mac; ./paste-tracker.pl"
screen -p 5 -X stuff "cd; genghisapp -L -F"
screen -p 6 -X stuff "AUTOSSH_POLL=30 AUTOSSH_DEBUG=1 autossh -M2000 -L6667:localhost:6667 -N cmyers.org"
