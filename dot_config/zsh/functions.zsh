code() {
  VSCODE_CWD="$PWD" open -n -b "com.microsoft.VSCode" --args "$@"
}

ccd() {
  [[ -z "$1" ]] && { echo "Usage: ccd <dir>"; return 1; }
  mkdir -p -- "$1" && cd -P -- "$1"
}

dab() {
  git branch --merged | grep -vE "^\*|main|master|develop" | xargs -n 1 git branch -d
}

kp() {
  if [[ -z "$1" ]]; then
    echo "Usage: kp <port>"
    return 1
  fi

  local port="$1"
  local pids
  pids=$(lsof -tiTCP:"$port" -sTCP:LISTEN)

  if [[ -z "$pids" ]]; then
    echo "No server listening on port $port"
    return 0
  fi

  echo "Processes listening on port $port:"
  lsof -nP -iTCP:"$port" -sTCP:LISTEN

  echo
  echo "Killing:"
  echo "$pids"
  kill -9 $pids
  echo "Done."
}

f() {
  local file
  file=$(fzf --preview 'bat --color=always --style=numbers --line-range=:500 {}' --height=60% --reverse)
  [[ -n "$file" ]] && "$EDITOR" "$file"
}

ports() {
  sudo lsof -i -P -n | grep LISTEN
}

pj() {
  jq . "$1"
}
