ava-shell () {
  local tmpfile=$(mktemp);
  trap 'rm -f $tmpfile' EXIT;
  if bento ava shell "$@" --result-file $tmpfile; then
    if [ -e "$tmpfile" ]; then
      local fixed_cmd=$(cat $tmpfile);
      print -z "$fixed_cmd";
    else
      echo "Apologies! Extracting command failed"
    fi
  else
    return 1
  fi
};
alias '?a'='ava-shell';
