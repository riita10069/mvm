---
name: mvm
description: Runs commands for the current repository inside a disposable AWS Lambda MicroVM with the `mvm` CLI (Amazon Linux 2023 arm64 with Claude Code, Codex, gh, Node 22, AWS CLI, Terraform, ...). Use when the user asks to run tests, builds, installs, servers or untrusted code "in a VM", "in a MicroVM", "in a sandbox", "on mvm" or "remotely" (「VM で実行して」「mvm で動かして」「隔離環境でテストして」「MicroVM でビルドして」), when a task is heavy or risky to run on the local machine, when Linux arm64 behaviour must be checked, or to start, find, suspend, resume or remove the user's MicroVMs.
---

# mvm

`mvm` starts a MicroVM from an image built by the repository's Terraform, logs in over SSH (a WebSocket through the MicroVM endpoint), and runs commands there. Each VM is identified by its id (`microvm-…`). Nothing is synced automatically: `mvm sync` pushes the local working tree to the VM one way, and results come back only through command output or `git push` from the VM.

You run on the local machine. Edit files locally as usual; use the VM to **run** things.

Always call the wrapper, which works from any shell:

```bash
MVM=~/code/github.com/riita10069/mvm/bin/mvm   # adjust if the repository lives elsewhere
```

## Workflow

1. **Find a VM for this repository** before starting one:
   ```bash
   $MVM ls        # ID, STATE, IMAGE, STARTED, LEFT, REPO (repos cloned or synced into it)
   ```
   Reuse a RUNNING or SUSPENDED VM whose REPO column lists this repository; a suspended VM resumes on the next command. Otherwise start one (step 2). Keep the id in a variable for the rest of the task.
2. **Start a VM** when none fits (about 15–20 s; costs money while it exists):
   ```bash
   ID=$($MVM up --no-login)      # run inside the repository: it clones origin + unpushed commits into ~/work/<repo>
   ```
   Only the id is printed on stdout; progress and the echoed `aws` calls go to stderr. `--no-clone` starts without the repository; `-i <image>` picks another image.
3. **Run commands with `exec`**:
   ```bash
   $MVM exec $ID --sync -- 'npm ci && npm test'
   $MVM exec $ID -- 'cd packages/api && pytest -x'
   $MVM exec $ID -- go test ./...
   ```
   - The command runs in the VM directory that matches your current local directory (`~/work/<repo>/<same subdir>`).
   - `--sync` first makes `~/work/<repo>` match the local working tree: HEAD (unpushed commits included), uncommitted changes, and untracked files that are not git-ignored. Use it whenever local files changed since the last sync. It discards uncommitted VM-side changes in that checkout; ignored files there (`node_modules`, build output) are kept.
   - One argument is a shell command line (pipes, `&&`, globs and env vars expand in the VM). Several arguments are an argv.
   - The exit code is the command's exit code. Lines starting with `+ ` on stderr are mvm echoing the `ssh`/`aws` calls it makes; ignore them when parsing output.
4. **When done**, leave the VM (it suspends itself after 15 idle minutes) or suspend it now with `$MVM stop $ID`. Ask the user before `$MVM rm $ID`.

## Use cases

| Case | Commands |
|---|---|
| Run the test suite on Linux arm64 | `$MVM exec $ID --sync -- 'make test'` |
| Heavy build that would load the laptop | `$MVM exec $ID --sync -- 'cargo build --release'` (install toolchains first, see below) |
| Run untrusted or risky code (install scripts, unknown repos) | `$MVM up --no-clone`, then `$MVM exec $ID -- 'git clone https://github.com/o/r && cd r && ./install.sh'` |
| Try a dependency upgrade without touching the local tree | `$MVM exec $ID --sync -- 'npm i some-lib@latest && npm test'` |
| Dev server / long-running process | start it in tmux: `$MVM exec $ID -- 'tmux new-session -d -s dev "npm run dev"'`; read output: `$MVM exec $ID -- 'tmux capture-pane -p -t dev'`; stop: `$MVM exec $ID -- 'tmux kill-session -t dev'` |
| Open a VM web server locally | `$MVM port $ID 3000` (blocks; run it as a background job, or ask the user to run it). Then `http://127.0.0.1:3000`. Use `$MVM port $ID 3000 13000` when the local port is taken. |
| Headless Claude Code or Codex in the VM (Bedrock, no API key) | `$MVM exec $ID -- 'claude -p "summarise the failing tests"'`, `$MVM exec $ID -- 'codex exec "…"'` |
| Bring a result file back | `$MVM exec $ID -- 'cat coverage/summary.txt' > summary.txt`, or for a directory `$MVM exec $ID -- 'tar -czf - dist' | tar -xzf -` |
| Work on GitHub from the VM | git and gh in the VM are authenticated (token in an in-memory credential cache): `$MVM exec $ID -- 'git push -u origin HEAD && gh pr create --fill'` |
| Another repository in the same VM | `cd` into it locally, then `$MVM clone $ID` (or `$MVM sync $ID`) |

## Rules for working through the VM

- **Not synced back.** Files the VM writes stay in the VM. Copy them out (table above) or commit and push from the VM before it ends.
- **Uncommitted local edits** reach the VM only with `--sync` / `mvm sync`. `mvm up` and `mvm clone` copy commits only. Untracked files that look like secrets (`.env*`, `*.pem`, `*.key`, `id_*`, `.npmrc`, `*.tfstate`, ...) are never synced.
- **Lifetime**: at most 8 hours (`LEFT` in `mvm ls`); a VM suspended for an hour is terminated. Everything outside what you pushed is lost then. If less than ~30 minutes remain before a long job, tell the user.
- **Platform**: Linux arm64. Binaries built on macOS will not run there, and the reverse.
- **Toolchains**: the image has git, gh, Node 22 + npm, system Python 3.9, uv, gcc/make, AWS CLI, Terraform, kubectl, helm, ripgrep, jq and similar CLIs. Language toolchains are installed on demand: `$MVM exec $ID -- 'mvm-install go rust python java ruby node-pm build'`. The disk is 8 GB in total, so install only what the task needs.
- **Credentials**: the VM's AWS access is its execution role (Bedrock models, logs). Never copy local secrets, `.env` files or credentials into the VM, and never print the GitHub token.
- **Interactive login** (`mvm <id>`, `mvm up` without `--no-login`) needs a terminal; agents cannot use it. Suggest it to the user instead (in Claude Code: `! mvm <id>`).

## Safety

Get explicit user approval before:

| Command | Effect |
|---|---|
| `mvm up` when the user did not ask for a VM | Creates a billable MicroVM |
| `mvm rm <id>` | Terminates the VM; unpushed work in it is lost. It asks y/N on a terminal but not without one, so ask the user first, and never pass `-y` on your own |
| `mvm sync <id>` on a VM where someone worked by hand | Discards uncommitted changes in that VM checkout |
| `terraform apply` / `terraform destroy` in the repository | Rebuilds or deletes the image and its roles |

`MVM_DRY=1 $MVM <command>` prints the `aws` calls that would change state without running them.

## Troubleshooting

- `could not list MicroVMs: aws failed` or errors from `aws`: credentials or region. `aws sts get-caller-identity`, and `MVM_REGION` (default `ap-northeast-1`), `MVM_PROFILE`.
- `no MicroVM image named 'mvm'`: the image has not been built in this region (`terraform apply` in `terraform/`, user approval needed).
- `did not accept SSH within 2 minutes`: run `$MVM ls`; if the VM is RUNNING, retry `$MVM exec $ID -- true`; otherwise remove it (with approval) and start another.
- A command hangs on connect after a long idle period: the VM is resuming; it takes a few seconds.
