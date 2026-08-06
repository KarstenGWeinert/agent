FROM ubuntu:24.04

## System basics 
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        openssh-server git wget unzip curl tmux less htop \
        r-base r-base-dev libcurl4-openssl-dev \
        libcurl4 libxml2-dev libssl-dev build-essential xclip ripgrep fd-find fzf \
	cmake libuv1-dev pandoc poppler-data libpoppler-cpp-dev \
	libopenblas0 libopenblas-dev \
        sudo gh tzdata \
	libfontconfig1-dev libfreetype6-dev libfribidi-dev libgit2-dev \
	libharfbuzz-dev libtiff-dev libwebp-dev libx11-dev \
	software-properties-common python3-pip \ 
    && add-apt-repository -y ppa:deadsnakes/ppa  \
    && apt-get update && apt-get install -y python3.14 python3.14-venv \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && ln -s $(which fdfind) /usr/local/bin/fd

# time zone
ENV TZ=Europe/Berlin
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    dpkg-reconfigure --frontend noninteractive tzdata

## Air (R formatter) 
RUN curl -LsSf https://github.com/posit-dev/air/releases/latest/download/air-installer.sh | sh \
    && cp /root/.local/bin/air /usr/local/bin/air \
    && rm -rf /root/.local \
    && air --version

## Tokei (Code zählen)
ENV RUSTUP_HOME=/opt/rust
ENV CARGO_HOME=/opt/rust
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path && \
    /opt/rust/bin/cargo install tokei --root /usr/local && \
    rm -rf /opt/rust

## Forgejo-CLI v0.6.0 
RUN curl -sL "https://codeberg.org/forgejo-contrib/forgejo-cli/releases/download/v0.6.0/forgejo-cli-x86_64-linux.tar.gz" \
    | tar -xzf - -C /usr/local/bin && \
    chmod +x /usr/local/bin/fj && \
    fj version

## Create user: agent (with passwordless sudo)
RUN useradd -m -s /bin/bash agent && \
    usermod -aG sudo agent && \
    echo "agent ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/agent && \
    chmod 0440 /etc/sudoers.d/agent

## Helix Editor
RUN HELIX_VERSION=$(curl -s "https://api.github.com/repos/helix-editor/helix/releases/latest" | grep -Po '"tag_name": "\K[^"]+') && \
    curl -L "https://github.com/helix-editor/helix/releases/download/${HELIX_VERSION}/helix-${HELIX_VERSION}-x86_64-linux.tar.xz" -o /tmp/helix-${HELIX_VERSION}-x86_64-linux.tar.xz && \
    tar -C /opt -xf /tmp/helix-${HELIX_VERSION}-x86_64-linux.tar.xz && \
    ln -sf /opt/helix-${HELIX_VERSION}-x86_64-linux/hx /usr/local/bin/hx && \
    rm /tmp/helix-${HELIX_VERSION}-x86_64-linux.tar.xz && \
	echo "export COLORTERM=truecolor" >> /home/agent/.bashrc
COPY hx_config.toml /home/agent/.config/helix/config.toml

## SSH Setup - ONLY agent allowed, key-only authentication
RUN mkdir -p /var/run/sshd && \
	ssh-keygen -A && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config && \
    echo "" >> /etc/ssh/sshd_config && \
    echo "# SSH hardening" >> /etc/ssh/sshd_config && \
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config && \
    echo "PermitEmptyPasswords no" >> /etc/ssh/sshd_config && \
    echo "KbdInteractiveAuthentication no" >> /etc/ssh/sshd_config && \
    echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config && \
    echo "AllowUsers agent" >> /etc/ssh/sshd_config && \
	echo "PermitUserEnvironment yes" >> /etc/ssh/sshd_config && \
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd

## DuckDB 
RUN DUCKDB_VERSION=$(curl -s https://api.github.com/repos/duckdb/duckdb/releases/latest | grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/') && \
    wget "https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/duckdb_cli-linux-amd64.zip" && \
    unzip duckdb_cli-linux-amd64.zip -d /usr/local/bin/ && \
    rm duckdb_cli-linux-amd64.zip && \
    chmod +x /usr/local/bin/duckdb

## Lea
RUN python3.14 -c "import sys; v = sys.version_info; assert (v.major, v.minor) >= (3, 14), f'Python {v.major}.{v.minor} < 3.14'"
RUN python3.14 -m venv /opt/lea-venv
RUN /opt/lea-venv/bin/pip install --upgrade pip
RUN /opt/lea-venv/bin/pip install lea-cli duckdb
ENV PATH="/opt/lea-venv/bin:${PATH}"

## Pre-create directories and ensure correct ownership
RUN mkdir -p /home/agent/.local/share /home/agent/.config && \
    mkdir -p /home/agent/.local/share/forgejo-cli && \
    chown -R agent:agent /home/agent

# === Frequently changing customizations start here ===

## Copy authorizedkeys
COPY authorizedkeys /tmp/authorizedkeys

## Per-user GitHub tokens for SSH login shells
RUN echo 'GITHUB_TOKEN_AGENT' >> /etc/environment && \
    echo 'GITHUB_TOKEN_NERT'   >> /etc/environment && \
    echo 'FORGEJO_TOKEN' >> /etc/environment && \
    echo 'DEEPSEEK_API_KEY' >> /etc/environment

RUN mkdir -p /home/agent/.ssh && \
    cp /tmp/authorizedkeys /home/agent/.ssh/authorized_keys && \
    chown -R agent:agent /home/agent/.ssh && \
    chmod 700 /home/agent/.ssh && \
    chmod 600 /home/agent/.ssh/authorized_keys && \
    rm /tmp/authorizedkeys
	
## tmux
COPY tmux.conf /etc/tmux.conf
RUN echo 'if [ -z "$TMUX" ] && [[ $- == *i* ]]; then exec tmux new-session -A -s main; fi' >> /home/agent/.bashrc && \
	chown -R agent:agent /home/agent/.bashrc

# opencode
RUN mkdir -p /home/agent/.config && chown agent:agent /home/agent/.config
COPY --chown=agent:agent opencode/ /home/agent/.config/opencode/

## mattpocock engineering skills (installed at build time from upstream)
RUN git clone --depth 1 https://github.com/mattpocock/skills /tmp/mattpocock-skills && \
    mkdir -p /home/agent/.config/opencode/skills && \
    for s in code-review codebase-design diagnosing-bugs domain-modeling grill-with-docs \
             implement research resolving-merge-conflicts tdd to-spec to-tickets triage wayfinder; do \
        cp -r /tmp/mattpocock-skills/skills/engineering/$s /home/agent/.config/opencode/skills/$s || exit 1; \
    done && \
    rm -rf /tmp/mattpocock-skills && \
    chown -R agent:agent /home/agent/.config/opencode

## R Configuration (Using PPM Binaries)
RUN R_VERSION=$(R --version | head -n 1 | sed -E 's/.*version ([0-9]+\.[0-9]+).*/\1/') && \
    echo "Detected R version: $R_VERSION" && \
    echo "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/noble/latest'), pkg.type = 'binary')" >> /usr/lib/R/etc/Rprofile.site && \
    echo "" >> /usr/lib/R/etc/Rprofile.site && \
    echo "# Custom q() that does not ask to save workspace by default" >> /usr/lib/R/etc/Rprofile.site && \
    echo "utils::assignInNamespace(" >> /usr/lib/R/etc/Rprofile.site && \
    echo "  'q'," >> /usr/lib/R/etc/Rprofile.site && \
    echo "  function(save = 'no', status = 0, runLast = TRUE) {" >> /usr/lib/R/etc/Rprofile.site && \
    echo "    .Internal(quit(save, status, runLast))" >> /usr/lib/R/etc/Rprofile.site && \
    echo "  }," >> /usr/lib/R/etc/Rprofile.site && \
    echo "  'base'" >> /usr/lib/R/etc/Rprofile.site && \
    echo ")" >> /usr/lib/R/etc/Rprofile.site && \
    R -q -e 'install.packages("pak", repos = "https://r-lib.github.io/p/pak/stable")' && \
    R -q -e 'pak::pkg_install(c("remotes", "data.table", "duckdb", "shiny", "bslib", "reactable", "plotly", "pdftools", \
		"RhpcBLASctl", "nanoparquet", "httr", "jsonlite", "jose", "R.utils", "roxygen2", "devtools", "tinytest", "languageserver"))'

USER agent
WORKDIR /home/agent

# Configure Git 
RUN git config --global credential.https://github.com.helper "!gh auth git-credential" && \                            
    git config --global credential.http://forgejo:3000.helper '!f() { echo "username=kgw-agent"; echo "password=$FORGEJO_TOKEN"; }; f' && \
    git config --global user.name "OpenCode Agent" && \
    git config --global user.email "agent@opencode.local" 

# opencode
RUN curl -fsSL https://opencode.ai/install | bash

# lintr config
COPY --chown=agent:agent lintr_config /home/agent/.lintr

USER root

## sshd requires root
HEALTHCHECK --interval=60s --timeout=20s --start-period=120s --retries=3 \
    CMD bash -c 'echo -n > /dev/tcp/127.0.0.1/22' || exit 1
EXPOSE 22

## Entrypoint 
RUN echo '#!/bin/bash' > /usr/local/bin/entrypoint.sh && \
	echo 'echo "GH_TOKEN=${GITHUB_TOKEN_AGENT}" > /home/agent/.ssh/environment' >> /usr/local/bin/entrypoint.sh && \
	echo 'echo "FORGEJO_TOKEN=${FORGEJO_TOKEN}" >> /home/agent/.ssh/environment' >> /usr/local/bin/entrypoint.sh && \
	echo 'echo "DEEPSEEK_API_KEY=${DEEPSEEK_API_KEY}" >> /home/agent/.ssh/environment' >> /usr/local/bin/entrypoint.sh && \
	echo 'cat > /home/agent/.local/share/forgejo-cli/keys.json <<EOF' >> /usr/local/bin/entrypoint.sh && \
	echo '{"hosts":{"forgejo:3000":{"type":"Application","token":"$FORGEJO_TOKEN"}},"aliases":{},"default_ssh":[]}' >> /usr/local/bin/entrypoint.sh && \
	echo 'EOF' >> /usr/local/bin/entrypoint.sh && \
	echo 'chown agent:agent /home/agent/.ssh/environment /home/agent/.local/share/forgejo-cli/keys.json' >> /usr/local/bin/entrypoint.sh && \
	echo 'chmod 600 /home/agent/.ssh/environment /home/agent/.local/share/forgejo-cli/keys.json' >> /usr/local/bin/entrypoint.sh && \
	echo 'exec /usr/sbin/sshd -D' >> /usr/local/bin/entrypoint.sh && \
	chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

