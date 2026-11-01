# mvm: Lambda MicroVM development environments from zsh.  source this file from ~/.zshrc.
#
#   mvm up [-i image] [--no-clone] [--no-login]
#                                    start a VM, seed the GitHub token, clone the current repo, log in
#                                    (no login without a terminal: the id is printed on stdout instead)
#   mvm ls [-a] [--tsv]              list VMs (-a: include terminated ones, --tsv: no header, tab-separated)
#   mvm <id>                         log in (same as `ssh <id>`); a suspended VM resumes on connect
#   mvm <id> <action>                stop | resume | rm | clone | sync | exec | port | gh-login | ssh
#   mvm sync <id>                    make ~/work/<repo> match this working tree (uncommitted changes too)
#   mvm exec <id> [--sync] -- <cmd>  run cmd in the VM directory matching the current one
#   mvm port <id> <port> [local]     forward 127.0.0.1:<local> to the VM's port until Ctrl-C
#   mvm <id> -- <cmd...>             run a command in the VM
#   mvm clone <id>                   bring the current repo (origin + unpushed commits) into ~/work
#   mvm gh-login <id>                (re)seed the GitHub token into the VM's in-memory git credential cache
#   mvm stop|resume|rm <id>          suspend / resume / terminate (rm asks first; -y skips)
#
# TAB completes everything above: actions, then only the VMs whose state fits, described by state,
# image, start time, time left and the repos cloned into them. Typing part of a repo name, state or id
# and pressing TAB picks that VM. On a finished command line, TAB shows what Enter will do.
# Every AWS call is echoed to stderr as it runs (except the silent lookups behind TAB completion).
# MVM_DRY=1 echoes the calls that change state instead of running them.
# Settings (environment): MVM_REGION, MVM_PROFILE, MVM_IMAGE, MVM_GH_TOKEN_CMD, MVM_IDLE_SECONDS,
# MVM_NO_ZLE=1 (keep your TAB binding untouched), MVM_NO_STYLES=1 (no menu/colour zstyles),
# MVM_MASK_ACCOUNT=1 (hide AWS account ids in the echoed aws commands).
# The SSH key (~/.ssh/mvm_ed25519) and cache (~/.cache/mvm) are fixed because ssh/config names them.

: ${MVM_REGION:=ap-northeast-1}
: ${MVM_IMAGE:=mvm}
: ${MVM_GH_TOKEN_CMD:=gh auth token}
: ${MVM_IDLE_SECONDS:=900}
export MVM_REGION MVM_PROFILE
typeset -g MVM_MAX_SECONDS=28800
typeset -g MVM_KEY=$HOME/.ssh/mvm_ed25519 MVM_CACHE=$HOME/.cache/mvm
typeset -g MVM_ROOT=${${(%):-%x}:A:h:h}
typeset -gU path   # -g: ~/.zshrc may wrap `source` in a function
path=($MVM_ROOT/bin "${path[@]}")
zmodload zsh/datetime
mkdir -p -m 700 $MVM_CACHE

_mvm_say() { emulate -L zsh; print -ru2 -- "mvm: $*" }

# _mvm_aws [-w] args...: run `aws <args>` in the configured region, echoing it first.
# -w marks a state-changing call, which MVM_DRY=1 only echoes.
_mvm_aws() {
  emulate -L zsh -o extendedglob
  local write=0
  [[ $1 == -w ]] && { write=1; shift }
  local -a cmd=(aws --region $MVM_REGION ${MVM_PROFILE:+--profile} ${MVM_PROFILE:+$MVM_PROFILE} "$@")
  local shown="+ ${(j: :)${(@q-)cmd}}"
  # MVM_MASK_ACCOUNT=1 hides AWS account ids in the echo (screen sharing, recordings).
  [[ ${MVM_MASK_ACCOUNT:-} == 1 ]] && shown=${shown//:[0-9](#c12):/:************:}
  print -ru2 -- $shown
  (( write )) && [[ ${MVM_DRY:-} == 1 ]] && return 0
  command "${cmd[@]}"
}

# The same settings as ssh/config's Host microvm-*, passed on the command line so that mvm works
# without the Include in ~/.ssh/config (plain ssh, scp and VS Code still need the Include).
typeset -ga _MVM_SSH_OPTS=(
  -o User=dev -o IdentityFile=$MVM_KEY -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$MVM_CACHE/known_hosts
  -o "ProxyCommand=$MVM_ROOT/bin/mvm-proxy %h"
  -o ServerAliveInterval=30 -o ServerAliveCountMax=4
  -o ControlMaster=auto -o "ControlPath=$MVM_CACHE/cm-%C" -o ControlPersist=120
  -o ForwardAgent=no -o SendEnv=LANG -o "SendEnv=LC_*" -o LogLevel=ERROR
)
_mvm_ssh_raw() { command ssh "${_MVM_SSH_OPTS[@]}" "$@" }
# -t only with a terminal on both ends (coding agents and scripts have none).
_mvm_tty() { [[ -t 0 && -t 1 ]] && print -r -- -t }
_mvm_ssh() { emulate -L zsh; print -ru2 -- "+ ssh ${(j: :)${(@q-)@}}"; _mvm_ssh_raw "$@" }

_mvm_check_id() {
  emulate -L zsh
  [[ $1 == microvm-* ]] && return 0
  _mvm_say "expected a MicroVM id (microvm-...), got '${1:-}'"; return 2
}

typeset -ga _MVM_ACTIONS=(stop suspend resume rm down clone gh-login ssh sync exec port)

mvm() {
  emulate -L zsh
  local sub=${1:-ls}
  (( $# )) && shift
  case $sub in
    up)        _mvm_up "$@" ;;
    ls|list)   _mvm_ls "$@" ;;
    clone)     _mvm_clone "$@" ;;
    gh-login)  _mvm_gh_login "$@" ;;
    stop|suspend) _mvm_check_id "${1:-}" && _mvm_aws -w lambda-microvms suspend-microvm --microvm-identifier "$1" && _mvm_forget_list ;;
    resume)    _mvm_check_id "${1:-}" && _mvm_aws -w lambda-microvms resume-microvm --microvm-identifier "$1" && _mvm_forget_list ;;
    rm|down)   _mvm_rm "$@" ;;
    ssh)       _mvm_check_id "${1:-}" && _mvm_ssh $(_mvm_tty) "$1" ;;
    sync)      _mvm_sync "$@" ;;
    exec)      _mvm_exec "$@" ;;
    port)      _mvm_port "$@" ;;
    microvm-*)
      # mvm <id> [action | -- cmd...]: VM first, then what to do with it (the order TAB offers).
      if (( ! $# )); then _mvm_ssh $(_mvm_tty) $sub
      elif [[ $1 == -- ]]; then shift; _mvm_ssh $(_mvm_tty) $sub "$@"
      elif (( ${_MVM_ACTIONS[(Ie)$1]} )); then local action=$1; shift; mvm $action $sub "$@"
      else _mvm_ssh $(_mvm_tty) $sub "$@"
      fi ;;
    help|-h|--help) sed -n '2,26p' $MVM_ROOT/shell/mvm.zsh | sed 's/^# \{0,1\}//' ;;
    *) _mvm_say "unknown command '$sub' (mvm help)"; return 2 ;;
  esac
}

_mvm_rm() {
  emulate -L zsh
  local yes=0
  [[ ${1:-} == (-y|--yes) ]] && { yes=1; shift }
  [[ ${2:-} == (-y|--yes) ]] && yes=1
  _mvm_check_id "${1:-}" || return
  local id=$1
  if (( ! yes )) && [[ -t 0 && ${MVM_DRY:-} != 1 ]]; then
    local repos=$(_mvm_repos $id)
    read -q "?mvm: terminate ${id}${repos:+ (~/work/${repos})}? Unpushed work in it is lost. [y/N] " || { print; return 1 }
    print
  fi
  _mvm_aws -w lambda-microvms terminate-microvm --microvm-identifier $id || return
  [[ ${MVM_DRY:-} == 1 ]] || { _mvm_ssh_raw -O exit $id 2>/dev/null; rm -rf -- $MVM_CACHE/$id; _mvm_forget_list }
}

# list-microvms JSON -> TSV rows: id, state, image:version, started (local), time left, start epoch.
# The AWS CLI prints local offsets ("2026-10-25T17:43:51.123000+09:00"); jq's strptime %z is unreliable
# on macOS, so the offset is applied by hand.
typeset -g _MVM_JQ_ROWS='
  def epoch: sub("\\.[0-9]+"; "") | capture("^(?<b>.{19})(?<z>Z|[+-][0-9]{2}:[0-9]{2})$") as $c
    | ($c.b + "Z" | fromdateiso8601)
      - (if $c.z == "Z" then 0 else ($c.z[0:1] + "1" | tonumber) * (($c.z[1:3] | tonumber) * 3600 + ($c.z[4:6] | tonumber) * 60) end);
  .items | map(. + {t: (if .startedAt then .startedAt | epoch else now end)}) | sort_by(-.t)[]
  | select($all or (.state | test("^TERMINAT") | not))
  | (.t + $max - now | floor) as $left
  | [.microvmId, .state, (.imageArn | split(":") | last) + ":" + (.imageVersion // "?"),
     (.t | strflocaltime("%m-%d %H:%M")),
     (if $left > 0 and (.state | test("^TERMINAT") | not) then "\($left / 3600 | floor)h\($left % 3600 / 60 | floor)m" else "-" end),
     (.t | floor)]
  | @tsv'

# Repositories `mvm clone` put on a VM (recorded locally; shown by ls and completion).
_mvm_repos() { emulate -L zsh; [[ -r $MVM_CACHE/$1/repos ]] && print -r -- ${(j:,:)${(f)"$(<$MVM_CACHE/$1/repos)"}} }

_mvm_ls() {
  emulate -L zsh
  local all=false tsv=0 json row id st img started left t
  while (( $# )); do
    case $1 in
      -a|--all) all=true ;;
      --tsv) tsv=1 ;;
      *) _mvm_say "usage: mvm ls [-a] [--tsv]"; return 2 ;;
    esac
    shift
  done
  json=$(_mvm_aws lambda-microvms list-microvms --output json) || return
  local -a rows=(${(f)"$(jq -r --argjson max $MVM_MAX_SECONDS --argjson all $all $_MVM_JQ_ROWS <<<$json)"})
  # --tsv: the same columns without the header, for scripts such as a session picker
  if (( tsv )); then
    for row in $rows; do
      IFS=$'\t' read -r id st img started left t <<<$row
      print -r -- "$id"$'\t'"$st"$'\t'"$img"$'\t'"$started"$'\t'"$left"$'\t'"$(_mvm_repos $id)"
    done
    return 0
  fi
  {
    print -r -- $'ID\tSTATE\tIMAGE\tSTARTED\tLEFT\tREPO'
    for row in $rows; do
      IFS=$'\t' read -r id st img started left t <<<$row
      print -r -- "$id"$'\t'"$st"$'\t'"$img"$'\t'"$started"$'\t'"$left"$'\t'"$(_mvm_repos $id)"
    done
  } | column -t -s $'\t'
  if (( ! $#rows )); then
    if [[ $all == true ]]; then _mvm_say "no MicroVMs in ${MVM_REGION}"
    else _mvm_say "no MicroVMs in ${MVM_REGION} (mvm ls -a also shows terminated ones)"
    fi
  fi
}

# Image name -> image ARN and the execution role from its mvm:execution-role tag (set by Terraform).
_mvm_image() {
  emulate -L zsh
  local name=$1 arn role
  arn=$(_mvm_aws lambda-microvms list-microvm-images --output text \
          --query "items[?name=='$name'].imageArn | [0]") || return
  [[ -n $arn && $arn != None ]] || { _mvm_say "no MicroVM image named '$name' in $MVM_REGION"; return 1 }
  role=$(_mvm_aws lambda-microvms get-microvm-image --image-identifier $arn --output text \
           --query 'tags."mvm:execution-role"') || return
  [[ -n $role && $role != None ]] || { _mvm_say "image $name has no mvm:execution-role tag"; return 1 }
  reply=($arn $role)
}

_mvm_up() {
  emulate -L zsh
  local image=$MVM_IMAGE clone=1 login=1 usage="usage: mvm up [-i image] [--no-clone] [--no-login]"
  [[ -t 0 && -t 1 ]] || login=0
  while (( $# )); do
    case $1 in
      -i|--image) (( $# >= 2 )) || { _mvm_say $usage; return 2 }; image=$2; shift 2 ;;
      --no-clone) clone=0; shift ;;
      --no-login) login=0; shift ;;
      *) _mvm_say $usage; return 2 ;;
    esac
  done
  local c
  for c in aws jq websocat ssh; do
    (( $+commands[$c] )) || { _mvm_say "$c is not installed"; return 1 }
  done
  if [[ ! -f $MVM_KEY ]]; then
    _mvm_say "creating SSH key $MVM_KEY"
    ssh-keygen -q -t ed25519 -N '' -C mvm -f $MVM_KEY || return
  fi

  local -a reply
  _mvm_image $image || return
  local arn=$reply[1] role=$reply[2]
  local payload
  payload=$(jq -nc --arg k "$(<$MVM_KEY.pub)" --arg r $MVM_REGION \
              --argjson exp $(( ($(date +%s) + MVM_MAX_SECONDS) * 1000 )) \
              '{authorizedKeys: $k, expiresAt: $exp, env: {AWS_REGION: $r, AWS_DEFAULT_REGION: $r}}')
  local out
  out=$(_mvm_aws -w lambda-microvms run-microvm --output json \
          --image-identifier $arn --execution-role-arn $role \
          --idle-policy maxIdleDurationSeconds=$MVM_IDLE_SECONDS,suspendedDurationSeconds=3600,autoResumeEnabled=true \
          --maximum-duration-in-seconds $MVM_MAX_SECONDS \
          --run-hook-payload $payload) || return
  [[ ${MVM_DRY:-} == 1 ]] && return 0
  local id=$(jq -r .microvmId <<<$out) endpoint=$(jq -r .endpoint <<<$out)
  mkdir -p -m 700 $MVM_CACHE/$id
  print -r -- $endpoint > $MVM_CACHE/$id/endpoint
  print -r -- $MVM_REGION > $MVM_CACHE/$id/region
  _mvm_say "started $id"
  _mvm_forget_list

  # The state from GetMicrovm is eventually consistent; SSH answering is the readiness signal.
  local deadline=$(( SECONDS + 120 ))
  until _mvm_ssh_raw -o ConnectTimeout=15 -o BatchMode=yes $id true 2>/dev/null; do
    (( SECONDS < deadline )) || { _mvm_say "${id} did not accept SSH within 2 minutes"; return 1 }
    sleep 2
  done

  # Progress goes to stderr: with --no-login, stdout carries only the id.
  _mvm_gh_login $id >&2 || _mvm_say "continuing without a GitHub token (run: mvm gh-login $id)"
  local dir='~/work'
  if (( clone )) && git rev-parse --show-toplevel >/dev/null 2>&1; then
    _mvm_clone $id >&2 && dir="~/work/${(qq)${$(git rev-parse --show-toplevel):t}}"
  fi
  if (( login )); then
    _mvm_ssh -t $id "cd $dir && exec \$SHELL -l"
  else
    # Without a login (scripts, coding agents), the id is the only thing printed on stdout.
    print -r -- $id
  fi
}

# mvm sync <id>: make ~/work/<repo> on the VM match this working tree, one way: HEAD (unpushed commits
# included), uncommitted changes and untracked files that are not ignored. Uncommitted VM-side changes
# in that checkout are discarded; ignored files there (node_modules, build output) are kept.
_mvm_sync() {
  emulate -L zsh -o pipefail
  _mvm_check_id "${1:-}" || return
  local id=$1 top name head br qn qh qb n
  top=$(git rev-parse --show-toplevel) || return
  name=${top:t} head=$(git -C $top rev-parse HEAD) br=$(git -C $top branch --show-current)
  [[ -n $br ]] || br=mvm-sync
  qn=${(qq)name} qh=${(qq)head} qb=${(qq)br}
  _mvm_ssh_raw -o BatchMode=yes $id "test -d ~/work/${qn}/.git" || { _mvm_clone $id || return }
  _mvm_ssh $id "cd ~/work/${qn} && { git fetch -q origin 2>/dev/null || true; }" || return
  if git -C $top remote get-url origin >/dev/null 2>&1; then
    n=$(git -C $top rev-list --count HEAD --not --remotes=origin)
  else
    n=$(git -C $top rev-list --count HEAD)
  fi
  if (( n > 0 )); then
    if git -C $top remote get-url origin >/dev/null 2>&1; then
      git -C $top bundle create - HEAD --not --remotes=origin 2>/dev/null
    else
      git -C $top bundle create - HEAD 2>/dev/null
    fi | _mvm_ssh $id "set -e; b=\$(mktemp); trap 'rm -f \"\$b\"' EXIT; cat > \"\$b\"; cd ~/work/${qn}; git fetch -q \"\$b\" HEAD" || return
  fi
  _mvm_ssh $id "set -e; cd ~/work/${qn}; git checkout -q -f -B ${qb} ${qh}; git reset -q --hard ${qh}; git clean -fdq" || return
  local patch
  patch=$(git -C $top diff --binary HEAD | base64)
  if [[ -n $patch ]]; then
    print -r -- $patch | _mvm_ssh $id "cd ~/work/${qn} && base64 -d | git apply --binary --whitespace=nowarn" || return
  fi
  # Untracked files that look like secrets never leave this machine, even when not git-ignored.
  local -a untracked=(${(0)"$(git -C $top ls-files -z --others --exclude-standard)"}) skipped
  skipped=(${(M)untracked:#(|*/)(.env|.env.*|*.pem|*.key|*.p12|*.pfx|id_rsa*|id_ed25519*|id_ecdsa*|.npmrc|.pypirc|.netrc|credentials|*.tfstate|*.tfstate.*)})
  untracked=(${untracked:|skipped})
  (( $#skipped )) && _mvm_say "not syncing secret-looking untracked files: ${(j:, :)skipped}"
  if (( $#untracked )); then
    # macOS tar would add xattrs/AppleDouble files that GNU tar on the VM warns about.
    (cd $top && print -rN -- $untracked |
      COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata --no-acls --no-fflags --null -T - -czf -) |
      _mvm_ssh $id "tar -xzf - -C ~/work/${qn}" || return
  fi
  _mvm_note_repo $id $name
  _mvm_say "synced ${name} to ${id}:~/work/${name} ($(git -C $top rev-parse --short HEAD)${patch:+ + uncommitted}${untracked:+ + ${#untracked} untracked})"
}

# mvm exec <id> [--sync] -- <cmd...>: run cmd in the VM directory matching the current one
# (~/work/<repo>/<same subdirectory>, or the repo root if that directory is not in git);
# --sync first runs mvm sync. The exit code is the command's.
_mvm_exec() {
  emulate -L zsh
  _mvm_check_id "${1:-}" || return
  local id=$1 dosync=0 top rel=''
  shift
  [[ ${1:-} == --sync ]] && { dosync=1; shift }
  [[ ${1:-} == -- ]] && shift
  (( $# )) || { _mvm_say "usage: mvm exec <id> [--sync] -- <command...>"; return 2 }
  # One argument is a shell command line (pipes, &&, globs expand in the VM), as with `ssh host 'cmd'`;
  # several arguments are an argv, each word quoted.
  local cmd
  if (( $# == 1 )); then cmd=$1; else cmd=${(j: :)${(@q)@}}; fi
  top=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -n $top ]]; then
    (( dosync )) && { _mvm_sync $id >&2 || return }
    rel=${PWD:A}; rel=${rel#${top:A}}
    local base="~/work/${(qq)top:t}" cdto
    cdto="cd ${base}${rel:+/${(qq)${rel#/}}} 2>/dev/null || cd ${base}"
    _mvm_ssh $(_mvm_tty) $id "${cdto} && ${cmd}"
  else
    _mvm_ssh $(_mvm_tty) $id "${cmd}"
  fi
}

# mvm port <id> <vm-port> [local-port]: forward 127.0.0.1:<local-port> to the VM's port until Ctrl-C.
# The local side is bound to loopback only.
_mvm_port() {
  emulate -L zsh
  _mvm_check_id "${1:-}" || return
  local id=$1 rport=${2:-} lport=${3:-${2:-}}
  [[ $rport == <1-65535> && $lport == <1-65535> ]] || { _mvm_say "usage: mvm port <id> <vm-port> [local-port]"; return 2 }
  _mvm_say "http://127.0.0.1:${lport} -> ${id}:${rport} (Ctrl-C to stop)"
  # A connection of its own: through a ControlMaster the forward would outlive this command.
  _mvm_ssh -N -o ControlMaster=no -o ControlPath=none -o ExitOnForwardFailure=yes -L 127.0.0.1:${lport}:localhost:${rport} $id
}

# Seed `gh auth token` (or MVM_GH_TOKEN_CMD) into the VM over SSH stdin. It lands only in git's
# credential-cache daemon (memory, 8 h), never in argv, environment files or disk.
_mvm_gh_login() {
  emulate -L zsh
  _mvm_check_id "$1" || return
  local id=$1
  print -ru2 -- "+ ${MVM_GH_TOKEN_CMD} | ssh $id git credential approve"
  [[ ${MVM_DRY:-} == 1 ]] && return 0
  { eval "$MVM_GH_TOKEN_CMD" } 2>/dev/null | _mvm_ssh_raw -o BatchMode=yes $id \
    'IFS= read -r T && [ -n "$T" ] && printf "protocol=https\nhost=github.com\nusername=x-access-token\npassword=%s\n\n" "$T" | git credential approve'
}

# github remote URL -> https (the VM authenticates over HTTPS only).
_mvm_https_url() {
  emulate -L zsh
  local u=$1
  case $u in
    git@*:*)       u=${u#git@}; u="https://${u%%:*}/${u#*:}" ;;
    ssh://git@*)   u="https://${u#ssh://git@}" ;;
  esac
  print -r -- $u
}

# Clone the current repository into ~/work/<name> on the VM: from origin over HTTPS, then the local
# commits origin does not have yet as a git bundle over SSH stdin. Uncommitted changes stay here.
_mvm_clone() {
  emulate -L zsh
  _mvm_check_id "$1" || return
  local id=$1 top name url br n
  top=$(git rev-parse --show-toplevel) || return
  name=${top:t}
  br=$(git -C $top branch --show-current)
  [[ -n $br ]] || { _mvm_say "detached HEAD; check out a branch first"; return 1 }
  [[ -z $(git -C $top status --porcelain --untracked-files=no) ]] ||
    _mvm_say "warning: uncommitted changes in ${name} are not copied (commit them to bring them)"
  # Values pasted into remote shell commands are single-quoted with (qq); always braced so that
  # zsh never reads a following ':' as a history modifier.
  local qn=${(qq)name} qb=${(qq)br} qo=${(qq):-origin/${br}} qr=${(qq):-refs/remotes/origin/${br}}
  local ql=${(qq):-${br}:refs/mvm/local}

  url=$(git -C $top remote get-url origin 2>/dev/null)
  if [[ -z $url ]]; then
    _mvm_say "no origin; sending the whole '${br}' history as a bundle"
    git -C $top bundle create - $br 2>/dev/null | _mvm_ssh $id \
      "set -e; b=\$(mktemp); trap 'rm -f \"\$b\"' EXIT; cat > \"\$b\"; git clone -q -b ${qb} \"\$b\" ~/work/${qn}; git -C ~/work/${qn} remote remove origin" || return
    _mvm_note_repo $id $name
    return
  fi
  # An existing checkout may hold VM-side work: only fetch, never move its branches.
  if _mvm_ssh $id "test -d ~/work/${qn}/.git"; then
    _mvm_say "~/work/${name} already exists on ${id}; fetching origin only"
    _mvm_ssh $id "git -C ~/work/${qn} fetch -q origin && git -C ~/work/${qn} status -sb | head -1" || return
    _mvm_note_repo $id $name
    return
  fi
  local qu=${(qq)$(_mvm_https_url $url)}
  _mvm_ssh $id "set -e; git clone -q ${qu} ~/work/${qn}; cd ~/work/${qn};
    if git rev-parse -q --verify ${qr} >/dev/null; then git checkout -q -B ${qb} ${qo}; else git checkout -q -B ${qb}; fi" || return

  # Commits not on any origin ref (works without origin/HEAD and for branches never pushed).
  n=$(git -C $top rev-list --count $br --not --remotes=origin)
  if (( n > 0 )); then
    _mvm_say "sending ${n} local commit(s) not on origin"
    git -C $top bundle create - $br --not --remotes=origin 2>/dev/null | _mvm_ssh $id \
      "set -e; b=\$(mktemp); trap 'rm -f \"\$b\"' EXIT; cat > \"\$b\"; cd ~/work/${qn}; git fetch -q \"\$b\" ${ql}; git checkout -q -B ${qb} refs/mvm/local; git update-ref -d refs/mvm/local" || return
  fi
  _mvm_ssh $id "cd ~/work/${qn} && { git branch -q -u ${qo} 2>/dev/null || true; } && git log --oneline -1" || return
  _mvm_note_repo $id $name
}

_mvm_note_repo() {
  emulate -L zsh
  mkdir -p -m 700 $MVM_CACHE/$1
  grep -qxF -- $2 $MVM_CACHE/$1/repos 2>/dev/null || print -r -- $2 >> $MVM_CACHE/$1/repos
}

# ---- VM and image lists for completion (silent, cached in files) ----
# The VM list is reused for 10 s and the image list for 60 s. Typing `mvm ` prefetches both in the
# background (see the ZLE section), so TAB usually answers without waiting for AWS.
typeset -g MVM_LIST_TTL=10 MVM_IMAGE_TTL=60 _mvm_prefetch_at=0
typeset -ga _mvm_vm_rows _mvm_img_rows
# Set when the last list call failed, so completion can say "AWS failed" instead of "no VMs".
typeset -gA _mvm_list_failed

_mvm_aws_quiet() {
  command aws --region $MVM_REGION ${MVM_PROFILE:+--profile} ${MVM_PROFILE:+$MVM_PROFILE} \
    --cli-connect-timeout 5 --cli-read-timeout 10 "$@" 2>/dev/null
}

# _mvm_fresh <file> <seconds>: the file exists and is younger than that.
_mvm_fresh() { emulate -L zsh -o extendedglob; [[ -n $1(#qN.ms-$2) ]] }

# _mvm_fetch <vms|images>: refresh $MVM_CACHE/<kind>.tsv. Only one fetch per kind runs at a time
# (a lock directory, considered stale after 30 s), and a result is dropped if the list was
# invalidated (mvm stop/rm/...) while it was in flight, so a stale list is never written back.
_mvm_fetch() {
  emulate -L zsh -o pipefail -o extendedglob
  zmodload -F zsh/system p:sysparams
  local kind=$1 lock=$MVM_CACHE/.$1.lock gen tmp rc=0 pid
  if [[ -d $lock ]]; then
    # Taken over only when its owner is gone (killed shell) or it is far older than any aws run.
    pid=$(<$lock/pid) 2>/dev/null
    if [[ -n $lock(#qN/ms+120) ]] || { [[ -n $pid ]] && ! kill -0 $pid 2>/dev/null }; then
      rm -f -- $lock/pid; rmdir $lock 2>/dev/null
    fi
  fi
  mkdir $lock 2>/dev/null || return 2
  print -r -- $sysparams[pid] >| $lock/pid
  gen=$(<$MVM_CACHE/$kind.gen) 2>/dev/null
  tmp=$(mktemp $MVM_CACHE/.$kind.XXXXXX) || { rmdir $lock; return 1 }
  {
    if [[ $kind == vms ]]; then
      _mvm_aws_quiet lambda-microvms list-microvms --output json |
        jq -r --argjson max $MVM_MAX_SECONDS --argjson all false $_MVM_JQ_ROWS > $tmp 2>/dev/null
    else
      _mvm_aws_quiet lambda-microvms list-microvm-images --output json |
        jq -r '.items[] | select(.state | test("^DELET") | not) | [.name, (.latestActiveImageVersion // "-"), .state] | @tsv' > $tmp 2>/dev/null
    fi
    rc=$?
    if (( rc == 0 )) && [[ $(<$MVM_CACHE/$kind.gen) == $gen ]] 2>/dev/null; then
      mv -f -- $tmp $MVM_CACHE/$kind.tsv 2>/dev/null
      rm -f -- $MVM_CACHE/$kind.failed
    else
      (( rc )) && : >| $MVM_CACHE/$kind.failed
    fi
  } always {
    rm -f -- $tmp $lock/pid; rmdir $lock 2>/dev/null
  }
  return rc
}

# Invalidate the VM list after a state change (and bump its generation for in-flight fetches).
_mvm_forget_list() { print -r -- $EPOCHREALTIME >| $MVM_CACHE/vms.gen; rm -f -- $MVM_CACHE/vms.tsv }

# _mvm_load <vms|images> <ttl> <what>: make $MVM_CACHE/<kind>.tsv current, fetching when stale.
# If another fetch (the background prefetch) is running, wait for it at most 5 s, and only once per
# TAB press: one TAB calls this several times. _mvm_list_failed[kind] is 1 when aws failed and 2
# when it is still running; a stale list, if any, is then used as it is.
typeset -gF _mvm_waited_at=0
_mvm_load() {
  local kind=$1 ttl=$2 what=$3 i
  _mvm_list_failed[$kind]=0
  _mvm_fresh $MVM_CACHE/$kind.tsv $ttl && return
  zle && zle -R "mvm: asking AWS for ${what} in ${MVM_REGION}..."
  _mvm_fetch $kind
  if (( $? == 2 )); then
    if (( EPOCHREALTIME - _mvm_waited_at > 2 )); then
      for i in {1..50}; do
        [[ -d $MVM_CACHE/.$kind.lock ]] || break
        sleep 0.1
      done
      _mvm_waited_at=$EPOCHREALTIME
    fi
    [[ -d $MVM_CACHE/.$kind.lock ]] && { _mvm_list_failed[$kind]=2; return }
  fi
  _mvm_fresh $MVM_CACHE/$kind.tsv $ttl || [[ ! -e $MVM_CACHE/$kind.failed ]] || _mvm_list_failed[$kind]=1
}

# Load the cached VM rows (id, state, image, started, left, epoch), fetching first if stale.
_mvm_vms() {
  _mvm_load vms $MVM_LIST_TTL MicroVMs
  _mvm_vm_rows=(${(f)"$(<$MVM_CACHE/vms.tsv)"}) 2>/dev/null || _mvm_vm_rows=()
}

_mvm_images() {
  _mvm_load images $MVM_IMAGE_TTL 'MicroVM images'
  _mvm_img_rows=(${(f)"$(<$MVM_CACHE/images.tsv)"}) 2>/dev/null || _mvm_img_rows=()
}

# Left over by a shell that died mid-fetch.
() { emulate -L zsh -o extendedglob; rm -f -- $MVM_CACHE/.(vms|images).??????(N.mm+1) }

# _mvm_vm_field <id> <n>: field n (1-based) of that VM's cached row.
_mvm_vm_field() {
  local row=${(M)_mvm_vm_rows:#$1$'\t'*}
  [[ -n $row ]] && print -r -- ${${(ps:\t:)row}[$2]}
}

# "microvm-...  RUNNING    mvm:4.0  10-25 19:04  7h53m left  ~/work/hello"
_mvm_vm_desc() {
  local id st img started left t repo
  IFS=$'\t' read -r id st img started left t <<<$1
  repo=$(_mvm_repos $id)
  print -r -- "$id  ${(r:10:)st} ${(r:8:)img} $started  ${(l:5:)left} left${repo:+  ~/work/${repo//,/ ~/work/}}"
}

# ---- completion ----
# _mvm_complete_vms <state pattern> <what> [nofuzzy]: VM ids whose state matches. A word that is not an id
# prefix (part of a repo name, a state, an image, a piece of the id) is matched against the
# descriptions and replaced by the id.
_mvm_complete_vms() {
  local want=$1 what=$2 fuzzy=${3:-1} row w i
  local -a ids descs fids fdescs expl
  _mvm_vms
  for row in $_mvm_vm_rows; do
    [[ ${${(ps:\t:)row}[2]} == ${~want} ]] || continue
    ids+=(${row%%$'\t'*})
    descs+=("$(_mvm_vm_desc $row)")
  done
  if (( ! $#ids )); then
    if (( ${_mvm_list_failed[vms]:-0} == 2 )); then
      _message -r "still asking AWS for MicroVMs (slow answer); press TAB again in a moment"
    elif (( ${_mvm_list_failed[vms]:-0} )); then
      _message -r "could not list MicroVMs: aws failed (credentials? region ${MVM_REGION}? try mvm ls)"
    else
      _message -r "no ${what} MicroVM in ${MVM_REGION} (mvm up starts one, mvm ls -a lists all)"
    fi
    return 1
  fi
  w=$PREFIX$SUFFIX
  if [[ -n $w && microvm- != ${w}* && $w != microvm-* ]]; then
    (( fuzzy )) || return 1
    for i in {1..$#ids}; do
      [[ ${(L)descs[i]} == *${(L)w}* ]] && { fids+=($ids[i]); fdescs+=($descs[i]) }
    done
    (( $#fids )) || return 1
    _wanted -V microvms expl "${what} MicroVM matching '${w}'" compadd -U -l -d fdescs -a fids
    return
  fi
  _wanted -V microvms expl "${what} MicroVM (newest first)" compadd -l -d descs -a ids
}

# What can be done with this VM now, given its state.
_mvm_complete_vm_actions() {
  local id=$1 st
  _mvm_vms
  st=$(_mvm_vm_field $id 2)
  local -a acts
  case $st in
    RUNNING)  acts=('ssh:log in' 'stop:suspend it now (it also suspends itself when idle)'
                    'clone:bring the current repo and unpushed commits into ~/work'
                    'sync:make its checkout match this working tree' 'exec:run a command in the matching directory'
                    'port:forward one of its ports to 127.0.0.1'
                    'gh-login:seed the GitHub token again' 'rm:terminate it (asks first)'
                    '--:run a command in it') ;;
    SUSPEND*) acts=('resume:resume it' 'ssh:log in (resumes on connect)'
                    'clone:bring the current repo into ~/work (resumes on connect)'
                    'gh-login:seed the GitHub token again' 'rm:terminate it (asks first)'
                    '--:run a command in it (resumes on connect)') ;;
    PENDING)  acts=('ssh:log in once it is up' 'rm:terminate it (asks first)') ;;
    '')       _message -r "${id} is not a live MicroVM in ${MVM_REGION}"; return 1 ;;
    *)        acts=('rm:terminate it (asks first)') ;;
  esac
  _describe -V -t actions "actions for ${id} (${st})" acts
}

_mvm_complete_images() {
  local row name ver st
  local -a names descs expl
  _mvm_images
  for row in $_mvm_img_rows; do
    IFS=$'\t' read -r name ver st <<<$row
    names+=($name)
    descs+=("${(r:12:)name} latest ${(r:5:)ver} ${(r:8:)st}${${(M)name:#$MVM_IMAGE}:+  (default)}")
  done
  if (( ! $#names )); then
    if (( ${_mvm_list_failed[images]:-0} == 2 )); then _message -r "still asking AWS for MicroVM images; press TAB again in a moment"
    elif (( ${_mvm_list_failed[images]:-0} )); then _message -r "could not list MicroVM images: aws failed (try aws lambda-microvms list-microvm-images)"
    else _message -r "no MicroVM images in ${MVM_REGION} (terraform apply builds one)"
    fi
    return 1
  fi
  _wanted images expl 'MicroVM image' compadd -l -d descs -a names
}

_mvm() {
  local ret=1
  local -a subs=(
    'up:start a VM, seed the GitHub token, clone this repo and log in'
    'ls:list VMs'
    'stop:suspend a running VM'
    'resume:resume a suspended VM'
    'clone:bring the current repo (and unpushed commits) into a VM'
    'gh-login:seed the GitHub token into a VM again'
    'ssh:log in to a VM'
    'sync:make the VM checkout match this working tree (incl. uncommitted changes)'
    'exec:run a command in the matching VM directory'
    'port:forward a VM port to 127.0.0.1'
    'rm:terminate a VM (asks first)'
    'help:show usage'
  )
  local -a opt_all=('-a:also list terminated VMs') opt_yes=('-y:terminate without asking')
  if (( CURRENT == 2 )); then
    _describe -V -t commands 'mvm action' subs && ret=0
    # A word that starts an action name completes the action, not VMs matched by description.
    local fuzzy=1 w=$PREFIX$SUFFIX
    [[ -n $w ]] && (( ${subs[(I)${(b)w}*]} )) && fuzzy=0
    _mvm_complete_vms '(RUNNING|SUSPEND*|PENDING)' live $fuzzy && ret=0
    return ret
  fi
  case $words[2] in
    up)
      # _arguments parses from words[1]; drop "mvm" so that "up" is the command it sees.
      shift words; (( CURRENT-- ))
      _arguments -s : \
        '(-i --image)'{-i,--image}'[image to start]:image:_mvm_complete_images' \
        '--no-clone[start without cloning the current repository]' && ret=0 ;;
    # Flags only after a typed "-": TAB on a finished line must never add -a, let alone rm's -y.
    ls|list) (( CURRENT == 3 )) && [[ $PREFIX == -* ]] && _describe -t flags flag opt_all && ret=0 ;;
    stop|suspend) (( CURRENT == 3 )) && _mvm_complete_vms RUNNING running && ret=0 ;;
    resume) (( CURRENT == 3 )) && _mvm_complete_vms 'SUSPEND*' suspended && ret=0 ;;
    rm|down)
      if (( CURRENT == 3 )); then _mvm_complete_vms '*' live && ret=0
      elif (( CURRENT == 4 )) && [[ $PREFIX == -* ]]; then _describe -t flags flag opt_yes && ret=0
      fi ;;
    clone|gh-login|ssh|sync|port) (( CURRENT == 3 )) && _mvm_complete_vms '(RUNNING|SUSPEND*|PENDING)' live && ret=0 ;;
    exec)
      if (( CURRENT == 3 )); then _mvm_complete_vms '(RUNNING|SUSPEND*|PENDING)' live && ret=0
      elif (( CURRENT == 4 )); then
        local -a ex=('--sync:sync this working tree first' '--:then the command')
        _describe -V -t flags 'exec option' ex && ret=0
      else _message 'command to run in the VM'
      fi ;;
    microvm-*)
      if (( CURRENT == 3 )); then _mvm_complete_vm_actions $words[2] && ret=0
      elif [[ $words[3] == -- ]]; then _message 'command to run in the VM'
      elif [[ $words[3] == (rm|down) ]] && (( CURRENT == 4 )) && [[ $PREFIX == -* ]]; then
        _describe -t flags flag opt_yes && ret=0
      fi ;;
  esac
  return ret
}

_mvm_register_completion() {
  emulate -L zsh
  (( ${+functions[compdef]} )) || return 1
  compdef _mvm mvm
  add-zsh-hook -d precmd _mvm_register_completion 2>/dev/null
}
# Works whether this file is sourced before or after compinit.
autoload -Uz add-zsh-hook add-zle-hook-widget
_mvm_register_completion || add-zsh-hook precmd _mvm_register_completion

if [[ ${MVM_NO_STYLES:-} != 1 ]]; then
  # The first TAB already opens the selection menu, so repeated TABs walk it.
  zstyle ':completion:*:*:mvm:*' menu yes select
  zstyle ':completion:*:*:mvm:*' group-name ''
  zstyle ':completion:*:*:mvm:*:descriptions' format '%F{cyan}-- %d --%f'
  zstyle ':completion:*:*:mvm:*:messages' format '%F{yellow}%d%f'
  zstyle ':completion:*:*:mvm:*' list-colors '=*RUNNING*=32' '=*SUSPEND*=33' '=*PENDING*=36'
fi

# ssh/scp/rsync/sftp: complete live MicroVM ids plus the non-wildcard Host entries of ~/.ssh/config.
# (A hosts zstyle replaces zsh's default host list, so the config hosts are added back here.)
_mvm_ssh_hosts() {
  _mvm_vms
  local -a cfg=()
  [[ -r ~/.ssh/config ]] && cfg=(${${(M)${(f)"$(<~/.ssh/config)"}:#[Hh]ost [^*?]#}#[Hh]ost })
  reply=(${_mvm_vm_rows%%$'\t'*} ${=cfg})
}
zstyle -e ':completion:*:(ssh|scp|rsync|sftp):*' hosts '_mvm_ssh_hosts'

# ---- ZLE ----
# 1. While the line starts with `mvm `, the VM and image lists are refreshed in the background
#    (one fetch at a time; see _mvm_fetch).
# 2. TAB on an `mvm` line runs your usual TAB widget; when nothing is left to complete, it shows
#    under the prompt what Enter will do instead.
_mvm_zle_prefetch() {
  emulate -L zsh
  [[ $BUFFER == mvm(| *) ]] || return 0
  (( EPOCHSECONDS - _mvm_prefetch_at < 3 )) && return 0
  _mvm_prefetch_at=$EPOCHSECONDS
  _mvm_fresh $MVM_CACHE/vms.tsv $MVM_LIST_TTL || { _mvm_fetch vms } >/dev/null 2>&1 &!
  _mvm_fresh $MVM_CACHE/images.tsv $MVM_IMAGE_TTL || { _mvm_fetch images } >/dev/null 2>&1 &!
}

# Message for a complete `mvm ...` line, or nothing while arguments are still missing.
# It follows the dispatcher in mvm(): `mvm <id> <word>` is an action only for _MVM_ACTIONS words.
_mvm_preview() {
  emulate -L zsh
  local -a w=(${(z)BUFFER})
  local sub=${w[2]:-} id act desc row top rest yes=0
  local -a args
  _mvm_vms 2>/dev/null
  # Rebuild the "<action> <args>" that mvm() would dispatch, then read the args like _mvm_rm does.
  if [[ $sub == microvm-* ]]; then
    if (( $#w < 3 )); then act=ssh args=($sub)
    elif [[ ${w[3]} == -- ]]; then act=--; args=($sub); rest=${(j: :)w[4,-1]}
    elif (( ${_MVM_ACTIONS[(Ie)${w[3]}]} )); then act=${w[3]}; args=($sub ${w[4,-1]})
    else act=--; args=($sub); rest=${(j: :)w[3,-1]}
    fi
  else
    act=$sub args=(${w[3,-1]})
  fi
  if [[ $act == (rm|down) ]]; then
    [[ ${args[1]:-} == (-y|--yes) ]] && { yes=1; shift args }
    [[ ${args[2]:-} == (-y|--yes) ]] && yes=1
  fi
  id=${args[1]:-}
  [[ $act == suspend ]] && act=stop
  [[ $act == down ]] && act=rm
  if [[ -n $id ]]; then
    row=${(M)_mvm_vm_rows:#$id$'\t'*}
    if [[ -n $row ]]; then desc="$(_mvm_vm_desc $row)"; desc=${desc#"$id  "}
    else desc='(not in the live list)'
    fi
  fi
  case $act in
    up)
      local img=$MVM_IMAGE; (( ${w[(I)(-i|--image)]} )) && img=${w[${w[(I)(-i|--image)]}+1]:-$MVM_IMAGE}
      top=$(git rev-parse --show-toplevel 2>/dev/null)
      if [[ -n $top ]] && (( ! ${w[(Ie)--no-clone]} )); then
        print -r -- "Enter: start a VM from ${img}, clone ${top:t} ($(git -C $top branch --show-current 2>/dev/null)) into ~/work and log in"
      else
        print -r -- "Enter: start a VM from ${img} and log in (nothing cloned)"
      fi ;;
    ls|list) print -r -- "Enter: list MicroVMs in ${MVM_REGION}" ;;
    help) print -r -- "Enter: show usage" ;;
    ssh)      [[ -n $id ]] && print -r -- "Enter: log in to ${id}   ${desc}" ;;
    stop)     [[ -n $id ]] && print -r -- "Enter: suspend ${id}   ${desc}" ;;
    resume)   [[ -n $id ]] && print -r -- "Enter: resume ${id}   ${desc}" ;;
    rm)
      if [[ -n $id ]]; then
        if (( yes )); then print -r -- "Enter: terminate ${id} WITHOUT asking   ${desc}"
        else print -r -- "Enter: terminate ${id} (asks first)   ${desc}"
        fi
      fi ;;
    gh-login) [[ -n $id ]] && print -r -- "Enter: seed the GitHub token into ${id}" ;;
    clone)
      top=$(git rev-parse --show-toplevel 2>/dev/null)
      [[ -n $id ]] && print -r -- "Enter: ${top:+clone ${top:t} into ${id}:~/work}${top:-not in a git repository here}" ;;
    --) [[ -n $id && -n $rest ]] && print -r -- "Enter: run '${rest}' in ${id}" ;;
  esac
}

# The widget TAB had before mvm took it over, per keymap ("main" is resolved to emacs/viins).
typeset -gA _mvm_tab_orig
typeset -gi _mvm_tab_depth=0

# No emulate here: the wrapped widget (your completion) must run with your own options.
_mvm_tab() {
  local km=$KEYMAP orig
  [[ $km == main ]] && km=${${${(M)${(f)"$(bindkey -lL main)"}:#*-A *}#bindkey -A }%% *}
  orig=${_mvm_tab_orig[${km:-emacs}]:-expand-or-complete}
  # Re-entered (a plugin that saved TAB after us calls us back): fall back to plain completion
  # (the compsys widget, not the builtin .expand-or-complete, so mvm's own completion still runs).
  if (( _mvm_tab_depth )) || [[ $orig == _mvm_tab ]]; then
    zle expand-or-complete
    return
  fi
  _mvm_tab_depth=1
  {
    if [[ $LBUFFER == mvm\ * && -z $RBUFFER ]]; then
      local before=$BUFFER msg
      zle $orig
      # Nothing left to complete (compsys records the match count in _lastcomp): say what Enter does.
      if [[ $BUFFER == $before && $LBUFFER == *' ' ]] && (( ${${_lastcomp[nmatches]}:-0} == 0 )); then
        msg=$(_mvm_preview)
        [[ -n $msg ]] && zle -M "$msg"
      fi
    else
      zle $orig
    fi
  } always {
    _mvm_tab_depth=0
  }
}

# Plugins that bind TAB later (zeno.zsh, fzf-tab, fzf's completion.zsh, ...) and a deferred
# compinit (zsh-defer) are common, so the binding and the compdef are (re)checked at the start of
# every command line. String macros (bindkey -s) on TAB are left alone.
_mvm_zle_line_init() {
  emulate -L zsh
  (( ${+functions[compdef]} )) && (( ! ${+_comps[mvm]} )) && compdef _mvm mvm
  local km cur
  for km in emacs viins; do
    cur=${${(z)$(bindkey -M $km '^I')}[2]}
    [[ $cur == _mvm_tab ]] && continue
    [[ $cur == \"* ]] && continue
    if [[ $cur == (undefined-key|) ]]; then
      # Unbound after mvm had bound it: the user removed it on purpose (bindkey -r), keep it so.
      [[ -n ${_mvm_tab_orig[$km]:-} ]] && continue
      cur=expand-or-complete
    fi
    _mvm_tab_orig[$km]=$cur
    bindkey -M $km '^I' _mvm_tab
  done
}

if [[ ${MVM_NO_ZLE:-} != 1 ]] && [[ -o interactive ]]; then
  zle -N _mvm_tab
  zle -N _mvm_zle_prefetch
  zle -N _mvm_zle_line_init
  add-zle-hook-widget line-pre-redraw _mvm_zle_prefetch
  add-zle-hook-widget line-init _mvm_zle_line_init
fi
