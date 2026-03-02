setopt auto_cd extended_glob hist_ignore_dups share_history inc_append_history

bindkey "^[[1;5C" forward-word
bindkey "^[[1;5D" backward-word

eval "$(zoxide init zsh)"
