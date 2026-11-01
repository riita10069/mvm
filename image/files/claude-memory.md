# Environment: mvm MicroVM

- You are in an AWS Lambda MicroVM (Amazon Linux 2023, arm64). It lives at most 8 hours and may be suspended when idle; anything not pushed is lost when it ends.
- Repositories are under ~/work. Nothing here is synced with the user's machine: commit and `git push` to share work.
- git and gh authenticate to GitHub through git's in-memory credential cache. Never write tokens to files or print them.
- `sudo` works without a password. AWS access is only the execution role (Bedrock models and logs).
- Installed: git, gh, Node 22 + npm (for the coding agents), system Python 3.9, uv, gcc/make, AWS CLI, AWS CDK, Terraform, kubectl, helm, ripgrep, fd, fzf, bat, jq, yq, delta, lazygit, neovim, tmux, herdr, zoxide, eza, yazi, ghq, sheldon, deno, psql/mysql/redis clients.
- Language toolchains are not preinstalled (the disk is 8 GB in total). Install them with `mvm-install go|rust|python|java|ruby|node-pm|build|clang|gdb|valgrind`.
