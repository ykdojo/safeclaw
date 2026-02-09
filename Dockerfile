FROM ubuntu:noble

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=America/Los_Angeles
ARG NODE_VERSION=24
ARG PLAYWRIGHT_MCP_VERSION=0.0.62
ARG CLAUDE_CODE_VERSION=2.1.37
ARG GEMINI_CLI_VERSION=0.26.0

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
    apt-get install -y --no-install-recommends git openssh-client jq tmux ttyd && \
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

# === INSTALL node-lief, Slack SDK, and Gemini CLI ===

RUN npm install -g node-lief @slack/web-api @google/gemini-cli@${GEMINI_CLI_VERSION}
ENV NODE_PATH=/usr/lib/node_modules

# === INSTALL Claude Code (native binary) ===

USER sclaw
WORKDIR /home/sclaw

# Pre-configure Gemini CLI to use API key auth (no interactive prompt)
RUN mkdir -p /home/sclaw/.gemini && \
    echo '{"security":{"auth":{"selectedType":"gemini-api-key"}}}' > /home/sclaw/.gemini/settings.json
ENV PATH="/home/sclaw/.local/bin:${PATH}"
ENV DISABLE_AUTOUPDATER=1

# Auth: set these env vars for cloud deployment (no interactive login needed)
# - CLAUDE_CODE_OAUTH_TOKEN: run `claude setup-token` locally to generate
# - GH_TOKEN: run `gh auth token` locally to print current token

# Bake Claude config into image
COPY --chown=sclaw:sclaw setup/CLAUDE.md /home/sclaw/.claude/CLAUDE.md
COPY --chown=sclaw:sclaw setup/settings.json /home/sclaw/.claude/settings.json

# Install scripts (check-context hook, context bar status line)
RUN mkdir -p /home/sclaw/.claude/scripts && \
    curl -sLo /home/sclaw/.claude/scripts/check-context.sh \
      https://raw.githubusercontent.com/ykdojo/claude-code-tips/main/scripts/check-context.sh && \
    curl -sLo /home/sclaw/.claude/scripts/context-bar.sh \
      https://raw.githubusercontent.com/ykdojo/claude-code-tips/main/scripts/context-bar.sh && \
    chmod +x /home/sclaw/.claude/scripts/check-context.sh && \
    chmod +x /home/sclaw/.claude/scripts/context-bar.sh

RUN curl -fsSL https://claude.ai/install.sh | bash -s -- ${CLAUDE_CODE_VERSION}

# === SETUP Claude Code ===

# Install DX plugin and Playwright MCP server
RUN claude plugin marketplace add ykdojo/claude-code-tips && \
    claude plugin install dx@ykdojo && \
    claude mcp add playwright -- playwright-mcp --headless --browser chromium --no-sandbox

# Skip onboarding so CLAUDE_CODE_OAUTH_TOKEN works in interactive mode
# See: https://github.com/anthropics/claude-code/issues/8938
RUN jq '. + {hasCompletedOnboarding: true, bypassPermissionsModeAccepted: true, autoCompactEnabled: false}' /home/sclaw/.claude.json > /tmp/.claude.json.tmp && \
    mv /tmp/.claude.json.tmp /home/sclaw/.claude.json

# Set default model (must be after plugin install which rewrites settings.json)
RUN jq '. + {model: "claude-opus-4-6"}' /home/sclaw/.claude/settings.json > /tmp/settings.json.tmp && \
    mv /tmp/settings.json.tmp /home/sclaw/.claude/settings.json

# Shell aliases and shortcuts
COPY --chown=sclaw:sclaw setup/.bashrc /tmp/.bashrc
RUN cat /tmp/.bashrc >> /home/sclaw/.bashrc && rm /tmp/.bashrc

# ttyd wrapper script
COPY --chown=sclaw:sclaw setup/ttyd-wrapper.sh /home/sclaw/ttyd-wrapper.sh
RUN chmod +x /home/sclaw/ttyd-wrapper.sh

# Skills and tools
COPY --chown=sclaw:sclaw setup/skills /home/sclaw/.claude/skills
COPY --chown=sclaw:sclaw setup/tools /home/sclaw/tools

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

