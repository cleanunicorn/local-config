# Devbox image — one long-lived container per project folder (see devbox.zsh).
# Rebuild with `devbox_build`; move a project onto it with `devbox_recreate`.
FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
# Match the host user so files written into the bind-mounted /workspace stay
# owned by you on the host.
ARG USER_UID=1000
ARG USER_GID=1000
# Host docker group's gid (devbox_build passes it). Devboxes started with
# --docker join this gid to use the socket; naming it here keeps `groups`
# from warning "cannot find name for group ID".
ARG DOCKER_GID=983

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg git build-essential python3 python3-pip \
      ripgrep jq less vim sudo procps bsdextrautils locales openssh-client unzip socat \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Node 22 — the version this repo's CI pins.
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Docker client + compose/buildx plugins (no daemon). Only useful in devboxes
# started with --docker, which mount the host's socket.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
      docker-ce-cli docker-compose-plugin docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/*
# Links --docker devboxes to their compose stacks; /usr/local/bin/docker
# shadows the real /usr/bin/docker (see the scripts for details).
COPY --chmod=0755 bin/docker bin/devbox-compose-link /usr/local/bin/

# Herdr — terminal multiplexer for coding agents. Single static binary from
# GitHub releases. HERDR_VERSION is a release number or "latest"; devbox_build
# passes a fresh HERDR_CACHE_BUST so "latest" is re-downloaded on every build
# (only this layer and the ones after it rebuild).
ARG HERDR_VERSION=latest
ARG HERDR_CACHE_BUST=0
RUN case "$(dpkg --print-architecture)" in \
      amd64) arch=x86_64 ;; \
      arm64) arch=aarch64 ;; \
      *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac \
    && if [ "$HERDR_VERSION" = latest ]; then path=latest/download; else path="download/v${HERDR_VERSION}"; fi \
    && curl -fsSL "https://github.com/herdrdev/herdr/releases/${path}/herdr-linux-${arch}" \
      -o /usr/local/bin/herdr \
    && chmod +x /usr/local/bin/herdr

# ubuntu:24.04 ships a stock `ubuntu` user on uid 1000; drop it so `dev` can
# take that uid.
RUN (userdel -r ubuntu 2>/dev/null || true) \
    && groupadd -g ${USER_GID} dev \
    && useradd -m -s /bin/bash -u ${USER_UID} -g ${USER_GID} dev \
    && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
    && chmod 0440 /etc/sudoers.d/dev \
    && (getent group ${DOCKER_GID} >/dev/null || groupadd -g ${DOCKER_GID} docker) \
    # /home/dev becomes each project's <name>-home volume, filled from here on
    # first use (so owned by dev). .claude and .history are where
    # CLAUDE_CONFIG_DIR and HISTFILE point.
    && mkdir -p /home/dev/.claude /home/dev/.history \
    && chown -R dev:dev /home/dev \
    # Shell config lives outside /home/dev, so it still reaches homes created
    # from an older image. Interactive bash reads /etc/bash.bashrc first.
    && printf '%s\n' '' \
      '# devbox: persistent history (HISTFILE is set in the image ENV).' \
      'case "$HISTFILE" in */*) mkdir -p "${HISTFILE%/*}" 2>/dev/null ;; esac' \
      'shopt -s histappend' \
      'case ";${PROMPT_COMMAND};" in *"history -a"*) ;; *) PROMPT_COMMAND="history -a;${PROMPT_COMMAND}" ;; esac' \
      >> /etc/bash.bashrc

USER dev
WORKDIR /home/dev
ENV LANG=en_US.UTF-8 \
    # Docker doesn't set SHELL; without it herdr/tmux panes start /bin/sh.
    SHELL=/bin/bash \
    PATH=/home/dev/.local/bin:$PATH \
    # Keeps credentials and .claude.json together (in the home volume).
    CLAUDE_CONFIG_DIR=/home/dev/.claude \
    HISTFILE=/home/dev/.history/bash_history

# Installs into ~/.local, so each new home volume starts with it; an existing
# home keeps its own copy, which Claude updates itself.
RUN curl -fsSL https://claude.ai/install.sh | bash

WORKDIR /workspace
CMD ["sleep", "infinity"]
