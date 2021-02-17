EI_CONFIG_PATH=${HOME}/.config/ei
CDRP_ROOT_FILE=${EI_CONFIG_PATH}/cdrp_dir

# cdrp system
# cdrp cd's to a source control repo
cdrp () {
  if ! setupCdrp; then
    # Setup failed (dir doesn't exist), just quit
    return 1
  fi

  if [[ $1 == "--help"  || $1 == "-h" || $1 == "-help" ]]; then
    cat <<USAGE
cdrp [dir]

cd to a specific repo.  Will prompt for root dir first time run.
Has tab completion

Examples:
# cd to base directory with repos
cdrp

# cd to env-improvement repo
cdrp env-improvement

# cd to a directory inside a repo
cdrp env-improvement/scripts

# Reset cdrp root dir
cdrpReset
USAGE
    return 1
  fi

  local dir=$(cdrpDir)

  if [[ $1 != "" ]]; then
    dir="${dir}/$1"
  fi

  if type realpath 1>/dev/null 2>/dev/null; then
    cd `realpath $dir`
  else
    cd $dir
  fi
}

cdrpReset () {
  echo Removing cdrp config, old directory: $(cdrpDir)
  rm ${CDRP_ROOT_FILE}
}

cdrpDir () {
  echo $(cat ${CDRP_ROOT_FILE})
}

setupCdrp () {
  local dir
  if [[ -e  $CDRP_ROOT_FILE ]]; then
    return
  fi

  echo -n "First time using cdrp!  Please enter your root directory for checkouts [~/repos]: "
  read dir

  if [[ $dir == "" ]]; then
    dir="~/repos"
  fi

  # Do glob expansion on string (i.e. convert ~ to $HOME)
  dir=${~dir}

  if [[ ! -d $dir ]]; then
    echo "$dir does not exist (or is not a directory), cannot use!"
    return 1
  fi

  echo Using $dir as checkout root
  echo $dir > ${CDRP_ROOT_FILE}

  return 0
}

# Autocomplete for cdrp
_cdrp() {
  _files -/ -W $(cdrpDir)
}

compdef _cdrp cdrp
