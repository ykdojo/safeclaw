FROM ubuntu:noble

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=America/Los_Angeles
ARG NODE_VERSION=24
ARG PLAYWRIGHT_MCP_VERSION=0.0.62
ARG CLAUDE_CODE_VERSION=2.1.250

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
    apt-get install -y --no-install-recommends git openssh-client jq tmux ttyd vim python3-pip unzip && \
    npm install -g yarn && \
    # clean apt cache
    rm -rf /var/lib/apt/lists/* && \
    # Create the sclaw user
    adduser sclaw

# === INSTALL Playwright MCP + browsers ===

ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# Install MCP globally, then prefetch the Chromium browser artifacts with curl.
# Playwright's own downloader has no stall timeout: on some networks the CDN
# connection establishes but then stops sending data mid-transfer, and the
# install hangs forever. curl's --speed-time aborts a stalled transfer and
# --retry reconnects until one succeeds. We fetch each artifact (URLs/paths come
# from --dry-run, so this stays version-agnostic) into Playwright's browser dir
# and mark it INSTALLATION_COMPLETE, so `playwright install` finds them already
# present and skips its download. The final install is a fast no-op verification
# (timeout-guarded so a missed artifact fails the build instead of hanging).
RUN npm install -g @playwright/mcp@${PLAYWRIGHT_MCP_VERSION} && \
    mkdir -p /ms-playwright && \
    PW=/usr/lib/node_modules/@playwright/mcp/node_modules/.bin/playwright && \
    "$PW" install-deps chromium && \
    "$PW" install --dry-run chromium | \
        awk '/Install location:/{loc=$3} /Download url:/{print loc, $3}' | \
        sort -u > /tmp/pw-pairs.txt && \
    while read -r loc url; do \
        echo "prefetching $loc"; \
        mkdir -p "$loc" || exit 1; \
        curl -fL --retry 8 --retry-all-errors --retry-delay 2 --connect-timeout 20 \
             --speed-limit 50000 --speed-time 15 -o /tmp/pw.zip "$url" || exit 1; \
        unzip -q -o /tmp/pw.zip -d "$loc" || exit 1; \
        touch "$loc/INSTALLATION_COMPLETE"; \
        rm -f /tmp/pw.zip; \
    done < /tmp/pw-pairs.txt && \
    timeout 300 "$PW" install chromium && \
    rm -f /tmp/pw-pairs.txt && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf ~/.npm/ && \
    chmod -R 777 /ms-playwright

# === INSTALL node-lief and Slack SDK ===

RUN npm install -g node-lief @slack/web-api
ENV NODE_PATH=/usr/lib/node_modules

# === INSTALL Claude Code (native binary) ===

USER sclaw
WORKDIR /home/sclaw

ENV PATH="/home/sclaw/.local/bin:${PATH}"
ENV DISABLE_AUTOUPDATER=1
ENV BASH_ENV=/home/sclaw/.env

# Auth: set these env vars for cloud deployment (no interactive login needed)
# - CLAUDE_CODE_OAUTH_TOKEN: run `claude setup-token` locally to generate
# - GH_TOKEN: run `gh auth token` locally to print current token

# Bake Claude config into image
COPY --chown=sclaw:sclaw setup/CLAUDE.md /home/sclaw/.claude/CLAUDE.md
COPY --chown=sclaw:sclaw setup/settings.json /home/sclaw/.claude/settings.json

# Install scripts (context bar status line)
RUN mkdir -p /home/sclaw/.claude/scripts && \
    curl -sLo /home/sclaw/.claude/scripts/context-bar.sh \
      https://raw.githubusercontent.com/ykdojo/claude-code-tips/main/scripts/context-bar.sh && \
    chmod +x /home/sclaw/.claude/scripts/context-bar.sh

RUN curl -fsSL https://claude.ai/install.sh | bash -s -- ${CLAUDE_CODE_VERSION}

# === SETUP Claude Code ===

# Install DX plugin and Playwright MCP server
ARG CLAUDE_CODE_TIPS_VERSION=v0.26.30
RUN claude plugin marketplace add https://github.com/ykdojo/claude-code-tips.git#${CLAUDE_CODE_TIPS_VERSION} && \
    claude plugin install dx@ykdojo && \
    claude mcp add playwright -- playwright-mcp --headless --browser chromium --no-sandbox

# Skip onboarding so CLAUDE_CODE_OAUTH_TOKEN works in interactive mode
# See: https://github.com/anthropics/claude-code/issues/8938
RUN jq '. + {hasCompletedOnboarding: true, autoCompactEnabled: false}' /home/sclaw/.claude.json > /tmp/.claude.json.tmp && \
    mv /tmp/.claude.json.tmp /home/sclaw/.claude.json

# Set default model (must be after plugin install which rewrites settings.json).
# Without this, the Claude API account defaults to Sonnet, not Opus.
RUN jq '. + {model: "claude-opus-5"}' /home/sclaw/.claude/settings.json > /tmp/settings.json.tmp && \
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

