# k8s aliases
alias 'kc=kubectl'
alias 'ks=kubectl -n kube-system'

ks-set-namespace() {
  kubectl config set-context --current --namespace=$1
}

ns-default() {
  ks-set-namespace default
}

ns-kube-system() {
  ks-set-namespace kube-system
}

kcdp() {
  kcd pod "$@"
}

# Only unalias if it exists (kubectl plugin used to create this alias)
[[ $(type -w kcp 2>/dev/null) == "kcp: alias" ]] && unalias kcp
kcp () {
  NAME=$1
  PATTERN="^"
  if [[ "-a" = ${NAME} ]]; then
    NAME=$2
    PATTERN=""
  fi

  kci pod ${NAME}
}

kcd() {
  kci "$@" | xargs -n 1 kubectl describe
}

kci() {
  TYPE=$1
  NAME=$2
  NO_TYPE=0

  if [[ -z ${NAME} ]]; then
    NAME=$1
    TYPE="all"
  fi

  kubectl get $TYPE -o json | jq -r '.items[] | select(.metadata.name | startswith("'${NAME}'")) | .kind + "/" + .metadata.name'
}
