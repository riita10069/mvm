# /etc/profile.d/zz-mvm.sh: login shells (bash and zsh).
# macOS may forward locales Linux lacks (e.g. LC_CTYPE=UTF-8); fall back to C.UTF-8.
_mvm_utf8() { [ -n "$1" ] && [ "$(LC_ALL="$1" locale charmap 2>/dev/null)" = "UTF-8" ]; }
_mvm_utf8 "${LANG:-}" || export LANG=C.UTF-8
if [ -n "${LC_ALL:-}" ] && ! _mvm_utf8 "$LC_ALL"; then unset LC_ALL; fi
if [ -n "${LC_CTYPE:-}" ] && ! _mvm_utf8 "$LC_CTYPE"; then unset LC_CTYPE; fi
unset -f _mvm_utf8

case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac
if [ -z "${TMUX:-}" ] && [ -r /etc/mvm-expires-at ]; then
  _mvm_left=$(( $(cat /etc/mvm-expires-at) - $(date +%s) ))
  if [ "$_mvm_left" -gt 0 ]; then
    printf 'mvm: %s expires in %dh%02dm. Code lives in ~/work; push before it ends.\n' \
      "${MVM_ID:-this MicroVM}" $((_mvm_left / 3600)) $((_mvm_left % 3600 / 60))
  fi
  unset _mvm_left
fi
