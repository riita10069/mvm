#!/usr/bin/env zsh
# tests/complete.zsh 'mvm stop ' ['mvm rm ' ...]: print the candidates TAB offers at the end of each line.
zmodload zsh/zpty zsh/datetime
local here=${0:A:h} q line out start l
export MVM_TEST_SRC=${MVM_TEST_SRC:-$here/../shell/mvm.zsh}
# MVM_TEST_STUB=1: tests/stub/aws first in PATH and a throwaway HOME (no AWS calls).
[[ ${MVM_TEST_STUB:-} == 1 ]] && export HOME=$(mktemp -d) PATH=$here/stub:$PATH
for q in "$@"; do
  zpty z 'TERM=xterm zsh -f -i'
  zpty -w z "source ${(q)here}/capture-setup.zsh"
  zpty -n -w z "$q"$'\t'
  out= start=$EPOCHREALTIME
  while (( EPOCHREALTIME - start < 30 )); do
    zpty -r -t z line && out+=$line || sleep 0.05
    [[ $out == *$'\x01E'* ]] && break
  done
  print -r -- "== [$q]"

  for l in ${(f)out}; do
    l=${l%$'\r'}
    case $l in
      $'\x01H'*) print -r -- "  ${l#$'\x01H'}" ;;
      $'\x01M'*) print -r -- "  (message) ${l#$'\x01M'}" ;;
    esac
  done
  [[ $out == *$'\x01E'* ]] || print -r -- "  (timed out)"
  zpty -d z
done
