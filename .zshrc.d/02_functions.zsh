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

