if [[ -e ~/site ]]; then
  if [[ -e ~/site/site.zsh ]]; then
    source ~/site/site.zsh
  fi

  export PATH=$PATH:~/site/bin
fi
