#!/usr/bin/env zsh
# tests/zle.zsh: drive the real TAB widget in a pseudo-terminal with key sequences and report the
# resulting command line (and any `zle -M` message such as the Enter preview).
#   tests/zle.zsh $'mvm stop \t' $'mvm \t\t\t\r'
# MVM_TEST_REAL=1 starts your normal interactive zsh (~/.zshrc, plugins) instead of `zsh -f`.
# MVM_TEST_PRE / MVM_TEST_POST: commands run before / after sourcing mvm.zsh (e.g. other TAB plugins).
# MVM_TEST_LATER: a command sent as its own line after the first prompt (e.g. a plugin loaded late).
# MVM_TEST_STUB=1 puts tests/stub/aws first in PATH and uses a throwaway HOME (no AWS calls).
zmodload zsh/zpty zsh/datetime
setopt extendedglob
local here=${0:A:h} keys out line start
# Keep reading while waiting: zle stalls its redraws (and hooks) when nobody reads the terminal.
_t_drain() { local l s=$EPOCHREALTIME; while (( EPOCHREALTIME - s < $1 )); do zpty -r -t z l && out+=$l || sleep 0.05; done }
if [[ ${MVM_TEST_STUB:-} == 1 ]]; then
  export HOME=$(mktemp -d) PATH=$here/stub:$PATH
fi
for keys in "$@"; do
  out=
  if [[ ${MVM_TEST_REAL:-} == 1 ]]; then
    zpty z 'TERM=xterm-256color COLUMNS=200 LINES=50 zsh -i'
    _t_drain 6
    zpty -w z "source ${(q)here}/../shell/mvm.zsh"
    _t_drain 4
    zpty -w z ':'
  else
    zpty z 'TERM=xterm COLUMNS=200 LINES=50 zsh -f -i'
    zpty -w z "PROMPT='%% ' RPROMPT=; autoload -Uz compinit && compinit -u -D; ${MVM_TEST_PRE:-:}; source ${(q)here}/../shell/mvm.zsh; ${MVM_TEST_POST:-:}"
    zpty -w z ':'
  fi
  zpty -w z '_t_buf() { print -rn -- $'"'"'\x01B'"'"'"$BUFFER"$'"'"'\x01E'"'"' >/dev/tty }; zle -N _t_buf; bindkey "^Xb" _t_buf'
  _t_drain 2
  [[ -n ${MVM_TEST_LATER:-} ]] && { zpty -w z "$MVM_TEST_LATER"; _t_drain 2; zpty -w z ':'; _t_drain 1 }
  out=
  zpty -n -w z "$keys"
  _t_drain 6
  zpty -n -w z $'\C-Xb'
  start=$EPOCHREALTIME
  while (( EPOCHREALTIME - start < 20 )); do
    zpty -r -t z line && out+=$line || sleep 0.05
    [[ $out == *$'\x01E'* ]] && break
  done
  print -r -- "== [${(V)keys}]"
  local plain=${out//$'\e'\[[0-9;?]#[a-zA-Z]/}
  plain=${plain//$'\r'/}
  print -r -- "  buffer: ${${plain##*$'\x01B'}%%$'\x01E'*}"
  local -a msg=(${(M)${(f)plain}:#*Enter: *})
  local c1=$'\x01' m
  if [[ -n $msg ]]; then m=${msg[-1]#*Enter: }; m=${m%%$c1*}; m=${m%%$'\e'*}; print -r -- "  message: Enter: $m"; fi
  zpty -d z
done
