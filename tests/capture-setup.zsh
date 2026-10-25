# Sourced inside the pseudo-terminal zsh by complete.zsh: load mvm, then report every candidate the
# completion system offers instead of drawing a menu. Markers are control characters so the echoed
# command line never contains them.
PROMPT= RPROMPT=
autoload -Uz compinit && compinit -u -D
source ${MVM_TEST_SRC:?}
zstyle ':completion:*' list-grouped false
zstyle ':completion:*' insert-tab false
typeset -g _cap_hit=$'\x01H' _cap_msg=$'\x01M' _cap_end=$'\x01E' _cap_buf=$'\x01B'
comppostfuncs=(_cap_finish)
_cap_finish() { builtin print -rn -- $'\n'"$_cap_end"$'\n' }
compadd() {
  if [[ ${@[1,(i)(-|--)]} == *-(O|A|D)\ * ]]; then builtin compadd "$@"; return; fi
  local -a __hits __dscr; local __i
  (( $@[(I)-d] )) && __dscr=("${(@P)${(v)@[$@[(I)-d]+1]}}")
  builtin compadd -A __hits -D __dscr "$@"
  for __i in {1..$#__hits}; do builtin print -rn -- $'\n'"$_cap_hit${__hits[__i]}${__dscr[__i]:+ :: ${__dscr[__i]}}"; done
}
_message() { builtin print -rn -- $'\n'"$_cap_msg${@[-1]}" }
bindkey '^I' complete-word
