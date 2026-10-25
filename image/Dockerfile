# mvm development image for Lambda MicroVMs (Linux arm64).
# Terraform zips this directory and builds it as a MicroVM image (terraform/image.tf).
# The snapshot is taken when mvm-agent answers /ready: nothing per-VM (keys, tokens) may be created here.
FROM public.ecr.aws/lambda/microvms:al2023-minimal

ENV LANG=C.UTF-8

# ---- OS packages ----
# dnf here is microdnf. curl stays curl-minimal (installing curl would conflict).
# The VM disk is a fixed 8 GB that this image shares with your work. Docs are skipped, and language
# toolchains are not baked in: only what the CLIs need (Node 22 for the coding agents, the system
# Python for mvm-agent, gcc/make for npm native modules). `mvm-install` adds Go, Rust, Java, ... on demand.
RUN dnf install -y --setopt=install_weak_deps=0 --setopt=tsflags=nodocs \
      openssh-server openssh-clients shadow-utils sudo procps-ng findutils which hostname less \
      diffutils patch file tree bc iproute iputils bind-utils nmap-ncat socat \
      telnet traceroute tcpdump strace lsof \
      git git-lfs jq tmux zsh vim-enhanced wget rsync tar gzip xz bzip2 zip unzip \
      make gcc gcc-c++ \
      python3 nodejs22 nodejs22-npm \
      sqlite postgresql16 mariadb105 redis6 \
      glibc-langpack-ja \
 && dnf clean all && rm -rf /var/cache/dnf \
 && ln -sf /usr/bin/node-22 /usr/bin/node && ln -sf /usr/bin/npm-22 /usr/bin/npm && ln -sf /usr/bin/npx-22 /usr/bin/npx \
 && rm -f /etc/ssh/ssh_host_*

# ---- Pinned single-binary tools (sha256 from the GitHub release digests) ----
ARG WEBSOCAT_VERSION=v1.14.1
ARG GH_VERSION=2.103.2
ARG RG_VERSION=15.2.0
ARG FD_VERSION=v10.5.0
ARG FZF_VERSION=0.74.5
ARG BAT_VERSION=v0.26.1
ARG YQ_VERSION=v4.54.1
ARG DELTA_VERSION=0.20.1
ARG NVIM_VERSION=v0.12.6
ARG UV_VERSION=0.13.5
ARG LAZYGIT_VERSION=0.66.2
ARG SHELLCHECK_VERSION=v0.11.0
ARG DIRENV_VERSION=v2.38.2
ARG KUBECTL_VERSION=v1.37.1
ARG HELM_VERSION=v4.3.1
RUN set -eu; \
    fetch() { curl -fsSL --retry 3 -o "$2" "$1" && echo "$3  $2" | sha256sum -c - >/dev/null; }; \
    t=$(mktemp -d); cd "$t"; \
    fetch https://github.com/vi/websocat/releases/download/${WEBSOCAT_VERSION}/websocat.aarch64-unknown-linux-musl websocat 711a69576a2ff473fb01a90ffafb571c2ed019e55479d7ae71b12c2eadeb7011; \
    install -m 0755 websocat /usr/local/bin/websocat; \
    fetch https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_arm64.tar.gz gh.tgz 4c3e99a50bd8b181a3fe9d69b25dd978bac768148d88f01507c6b4d1ef61a443; \
    mkdir -p /opt/gh && tar -xzf gh.tgz -C /opt/gh --strip-components=1; \
    fetch https://github.com/BurntSushi/ripgrep/releases/download/${RG_VERSION}/ripgrep-${RG_VERSION}-aarch64-unknown-linux-musl.tar.gz rg.tgz 800b1e7206afe799dfb5a6901f23147cfaabe0e52210538100f61e86e1740915; \
    tar -xzf rg.tgz --strip-components=1 --wildcards '*/rg' && install -m 0755 rg /usr/local/bin/rg; \
    fetch https://github.com/sharkdp/fd/releases/download/${FD_VERSION}/fd-${FD_VERSION}-aarch64-unknown-linux-musl.tar.gz fd.tgz d76c4317f7d5dba69f8a2a15856c90c777e7f0dd4e85f0de8c76de6992c374d4; \
    tar -xzf fd.tgz --strip-components=1 --wildcards '*/fd' && install -m 0755 fd /usr/local/bin/fd; \
    fetch https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_arm64.tar.gz fzf.tgz cf058001da21724a469b714a29cf4aab9cbe860d218a0d6c1b5b661efad7784c; \
    tar -xzf fzf.tgz fzf && install -m 0755 fzf /usr/local/bin/fzf; \
    fetch https://github.com/sharkdp/bat/releases/download/${BAT_VERSION}/bat-${BAT_VERSION}-aarch64-unknown-linux-musl.tar.gz bat.tgz 6369242c584065f195fb20cb36fbd7cb63ae690605bbe89868a7596b596c2c23; \
    tar -xzf bat.tgz --strip-components=1 --wildcards '*/bat' && install -m 0755 bat /usr/local/bin/bat; \
    fetch https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_arm64 yq 189088da0c6429ec5178dfaab1a114805f6cab0b61b165ab236efedf1d57a71b; \
    install -m 0755 yq /usr/local/bin/yq; \
    fetch https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-aarch64-unknown-linux-gnu.tar.gz delta.tgz da7f4338f593572ff426ae153e0870e2fdc72729416eff551b40cdeb67940db8; \
    tar -xzf delta.tgz --strip-components=1 --wildcards '*/delta' && install -m 0755 delta /usr/local/bin/delta; \
    fetch https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-arm64.tar.gz nvim.tgz 8f1f64a0bdb97247034038c3823c6cbad5bdf9ecd5751b85494b71c3ee04c815; \
    mkdir -p /opt/nvim && tar -xzf nvim.tgz -C /opt/nvim --strip-components=1 && ln -sf /opt/nvim/bin/nvim /usr/local/bin/nvim; \
    fetch https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-aarch64-unknown-linux-musl.tar.gz uv.tgz 7906c79adb21c81abd559841ba76bb1d9af9d791acac7a041b2972e03ae16538; \
    tar -xzf uv.tgz --strip-components=1 && install -m 0755 uv uvx /usr/local/bin/; \
    fetch https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_linux_arm64.tar.gz lazygit.tgz 79a3161eeb642f0473e23db6341f7baabd4a5933e921a9c1167c5d5c765c41a4; \
    tar -xzf lazygit.tgz lazygit && install -m 0755 lazygit /usr/local/bin/lazygit; \
    fetch https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.aarch64.tar.xz shellcheck.txz 12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588; \
    tar -xJf shellcheck.txz --strip-components=1 && install -m 0755 shellcheck /usr/local/bin/shellcheck; \
    fetch https://github.com/direnv/direnv/releases/download/${DIRENV_VERSION}/direnv.linux-arm64 direnv ec2a32dbe2f19dd085bd9315a1b4ea88b55ec288aa7eabe8723490baf466cb23; \
    install -m 0755 direnv /usr/local/bin/direnv; \
    fetch https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/arm64/kubectl kubectl ff749f4b78d9c4f1ec87307df9b50119ed819e2094aa9810cb9acffc3286c8c7; \
    install -m 0755 kubectl /usr/local/bin/kubectl; \
    fetch https://get.helm.sh/helm-${HELM_VERSION}-linux-arm64.tar.gz helm.tgz 8cf8f66ecbc252ac8f7f06cca68aba88508ddfde3a6a34feb1678ad1694b4f88; \
    tar -xzf helm.tgz --strip-components=1 linux-arm64/helm && install -m 0755 helm /usr/local/bin/helm; \
    cd / && rm -rf "$t"

# ---- AWS CLI v2 and Terraform (vendor-signed channels) ----
RUN set -eu; t=$(mktemp -d); cd "$t"; \
    curl -fsSL -o awscli.zip https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip && unzip -q awscli.zip && ./aws/install; \
    cd / && rm -rf "$t"; \
    curl -fsSL -o /etc/yum.repos.d/hashicorp.repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo; \
    dnf install -y --setopt=tsflags=nodocs terraform && dnf clean all && rm -rf /var/cache/dnf

# ---- Coding agents and JS tooling ----
# Opus/Sonnet 5.5 on Bedrock need Claude Code >= 2.1.280; fail the build rather than ship an older release.
ARG CLAUDE_CODE_MIN_VERSION=2.1.280
RUN npm install -g @anthropic-ai/claude-code@latest @openai/codex@latest @google/gemini-cli@latest \
      aws-cdk \
 && npm cache clean --force && rm -rf /root/.cache /root/.npm \
 && v="$(claude --version | awk '{print $1}')" && echo "claude-code $v" \
 && [ "$(printf '%s\n' "$CLAUDE_CODE_MIN_VERSION" "$v" | sort -V | head -1)" = "$CLAUDE_CODE_MIN_VERSION" ]

# ---- dev user, shell, git ----
COPY files/ /tmp/mvm-files/
RUN set -eu; f=/tmp/mvm-files; \
    useradd -m -s /bin/zsh dev && usermod -p '*' dev; \
    echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev && chmod 440 /etc/sudoers.d/dev; \
    install -d -o dev -g dev /opt/rust /opt/go; \
    install -m 0644 $f/sshd_config /etc/ssh/sshd_config; \
    install -m 0644 $f/profile.sh /etc/profile.d/zz-mvm.sh; \
    install -m 0644 $f/zshenv /etc/zshenv; \
    install -m 0644 $f/tmux.conf /etc/tmux.conf; \
    install -m 0755 $f/gh /usr/local/bin/gh; \
    install -m 0755 $f/mvm-install /usr/local/bin/mvm-install; \
    git config --system init.defaultBranch main; \
    git config --system core.quotepath false; \
    git config --system credential.helper 'cache --timeout=28800'; \
    git config --system core.pager delta; \
    install -d -o dev -g dev -m 0755 /home/dev/work /home/dev/.claude /home/dev/.codex /home/dev/.ssh; \
    chmod 0700 /home/dev/.ssh; \
    install -o dev -g dev -m 0644 $f/zshrc /home/dev/.zshrc; \
    install -o dev -g dev -m 0644 $f/claude-settings.json /home/dev/.claude/settings.json; \
    install -o dev -g dev -m 0644 $f/CLAUDE.md /home/dev/.claude/CLAUDE.md; \
    install -o dev -g dev -m 0644 $f/codex-config.toml /home/dev/.codex/config.toml; \
    install -d -m 0755 /opt/mvm && install -m 0755 $f/mvm-agent.py /opt/mvm/mvm-agent.py; \
    rm -rf $f

# mvm-agent: lifecycle hooks (:9000) and the WebSocket-to-sshd bridge (:2222).
EXPOSE 2222 9000
CMD ["/usr/bin/python3", "/opt/mvm/mvm-agent.py"]
