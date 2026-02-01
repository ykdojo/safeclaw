FROM ubuntu:noble

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=America/Los_Angeles
ARG NODE_VERSION=24
ARG PLAYWRIGHT_MCP_VERSION=0.0.62
ARG CLAUDE_CODE_VERSION=2.1.19

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# === INSTALL Node.js ===

RUN apt-get update && \
    # Install Node.js
    apt-get install -y curl wget gpg ca-certificates && \
    mkdir -p /etc/apt/keyrings && \
    curl -sL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_VERSION}.x nodistro main" >> /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && \
    apt-get install -y nodejs && \
    # Feature-parity with node.js base images.
    # Install GitHub CLI
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && \
    apt-get install -y gh && \
    apt-get install -y --no-install-recommends git openssh-client jq tmux && \
    npm install -g yarn && \
    # clean apt cache
    rm -rf /var/lib/apt/lists/* && \
    # Create the sclaw user
    adduser sclaw

# === INSTALL Playwright MCP + browsers ===

ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# Install MCP globally, then use its bundled Playwright to install Chromium
# This keeps browser versions in sync with the MCP package
RUN npm install -g @playwright/mcp@${PLAYWRIGHT_MCP_VERSION} && \
    mkdir /ms-playwright && \
    /usr/lib/node_modules/@playwright/mcp/node_modules/.bin/playwright install chromium --with-deps && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf ~/.npm/ && \
    chmod -R 777 /ms-playwright

# === INSTALL node-lief ===

RUN npm install -g node-lief
ENV NODE_PATH=/usr/lib/node_modules

# === INSTALL Claude Code (native binary) ===

USER sclaw
WORKDIR /home/sclaw
ENV PATH="/home/sclaw/.local/bin:${PATH}"
ENV DISABLE_AUTOUPDATER=1

# Auth: set these env vars for cloud deployment (no interactive login needed)
# - CLAUDE_CODE_OAUTH_TOKEN: run `claude setup-token` locally to generate
# - GH_TOKEN: run `gh auth token` locally to print current token

# Bake Claude config into image
COPY --chown=sclaw:sclaw setup/CLAUDE.md /home/sclaw/.claude/CLAUDE.md
COPY --chown=sclaw:sclaw setup/settings.json /home/sclaw/.claude/settings.json

# Install check-context hook script (auto half-clone at 80% context)
RUN mkdir -p /home/sclaw/.claude/scripts && \
    curl -sLo /home/sclaw/.claude/scripts/check-context.sh \
      https://raw.githubusercontent.com/ykdojo/claude-code-tips/main/scripts/check-context.sh && \
    chmod +x /home/sclaw/.claude/scripts/check-context.sh

RUN curl -fsSL https://claude.ai/install.sh | bash -s -- ${CLAUDE_CODE_VERSION}

# === PATCH Claude Code ===

RUN mkdir -p /tmp/patches && \
    cd /tmp && \
    curl -sLO https://raw.githubusercontent.com/ykdojo/claude-code-tips/main/system-prompt/${CLAUDE_CODE_VERSION}/patch-native.sh && \
    curl -sLO https://raw.githubusercontent.com/ykdojo/claude-code-tips/main/system-prompt/${CLAUDE_CODE_VERSION}/patch-cli.js && \
    curl -sLO https://raw.githubusercontent.com/ykdojo/claude-code-tips/main/system-prompt/${CLAUDE_CODE_VERSION}/native-extract.js && \
    curl -sLO https://raw.githubusercontent.com/ykdojo/claude-code-tips/main/system-prompt/${CLAUDE_CODE_VERSION}/native-repack.js && \
    curl -sL "https://api.github.com/repos/ykdojo/claude-code-tips/contents/system-prompt/${CLAUDE_CODE_VERSION}/patches" | \
    jq -r '.[].download_url' | xargs -I{} curl -sLO --output-dir patches {} && \
    chmod +x patch-native.sh && \
    ./patch-native.sh /home/sclaw/.local/share/claude/versions/${CLAUDE_CODE_VERSION} && \
    rm -rf /tmp/patches /tmp/*.sh /tmp/*.js

