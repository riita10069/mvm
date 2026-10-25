# Shell for the recorded demo (demo.tape points ZDOTDIR here): plain zsh + compinit + mvm.
setopt prompt_subst
autoload -Uz compinit && compinit -u -d /tmp/mvm-demo-zcompdump
export MVM_MASK_ACCOUNT=1 LANG=ja_JP.UTF-8
source ${ZDOTDIR:h:h}/shell/mvm.zsh
PROMPT='%F{213}❯%f %F{117}%1~%f %F{221}$(git branch --show-current 2>/dev/null)%f %# '
RPROMPT='%F{240}mac%f'
cd ${MVM_DEMO_REPO:-/tmp/mvm-demo/hello-world}
clear
