# tail last
tl()
{
  tail $1 `ls -t1 $2* | head -1`
}

# cd up a number of directories
u () {
    ud="."
    for i ( `seq 1 ${1-1}` ) {
      ud="${ud}/.."
    }

    cd $ud
}

# Find a file up, cd to that directory
up () {
        cd `findup $1`
        test -r $1 || cd -
}

here () {
  cd `pwd`
}

#color patterns
colorpattern(){
  sed -e "s/\($1\)/\o033[1;32m\1\o033[0m/g"
}

copy () {
  echo "$@" | xclip -i
}

# fix ME
more () {
  echo USE LESS YOU GIT
}

# print a range of lines from a file
middle () {
  sed -n -e $1','$2'p;'$2'q' $3
}

# Nested Screen
nsc () {
  # Change the current screen title
  echo -e -n '\033k'nsc: $1'\033\\'

  # fix higlighting: '

  # and invoke screen
  screen -c ~/.screenrc.nested -x -RR -e l -S "$@"
}

# Nested Screen
nesttm () {
  # Change the current screen title
  echo -e -n '\033k'nt: $1'\033\\'

  local TMUX=""

  # and invoke screen
  tmux attach-session -t "$@" || tmux new-session -s "$@"
}

mvscreenshot() {
    FILE=`ls -tr ~/Desktop/Screen\ Shot* | tail -n 1`
    mv $FILE ~/Desktop/$1
}

addVimPlugin() {
  local BASENAME=`basename $1 | sed 's/\.git$//'`

  # if [ -e $BASENAME ]; then
  #   echo Removing $BASENAME
  #   rm -rf $BASENAME
  # fi

  local STARTING_PWD=`pwd`
  cd

  echo git submodule add $1 .config/nvim/bundle/$BASENAME
  git submodule add $1 .config/nvim/bundle/$BASENAME

  cd $STARTING_PWD
}

nt() {
  tmux attach-session -t "$@" || tmux new-session -s "$@"
}

sslinfo () {
  echo | openssl s_client -showcerts -servername $1 -connect $1:443 2>/dev/null | openssl x509 -inform pem -noout -text
}
