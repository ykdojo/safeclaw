# SafeClaw architecture

## Overview

SafeClaw runs Claude Code inside a sandboxed Docker container, accessible via a web terminal. All authentication is handled via environment variables, making it easy to deploy locally or in the cloud.

## Web terminal

The user interacts with Claude Code through a browser, not a local terminal. This gives full access to the native Claude Code UI rather than building a custom one on top of the Agent SDK.

### Current approach: ttyd + tmux

- **ttyd** serves a web terminal over HTTP/WebSocket on port 7681
- **tmux** manages the Claude Code session inside the container
- One port, one ttyd process, one tmux session per container
- Full Claude Code UI - status line, colors, interactive prompts, everything
- No custom UI code needed

## Authentication

All secrets are stored on the host in `~/.config/safeclaw/.secrets/`. Each file becomes an environment variable (filename = env var name).

### How env vars are passed

1. `run.sh` reads all files in `.secrets/` and builds `-e NAME=value` flags
2. `docker exec` passes these to the `ttyd-wrapper.sh` process
3. The wrapper stores them in the tmux session via `tmux set-environment`
4. `.bashrc` loads them with `eval "$(tmux show-environment -s)"` so all shells (including Claude's bash commands) have access

### Claude Code

Token from `claude setup-token` is stored as `CLAUDE_CODE_OAUTH_TOKEN`. The Dockerfile sets `hasCompletedOnboarding: true` in `.claude.json` to skip the onboarding flow. Without this, interactive mode ignores the token and shows the login screen ([known issue](https://github.com/anthropics/claude-code/issues/8938)).

Known limitation: the token from `setup-token` has limited scopes (`user:inference` only), so `/usage` doesn't work and the status bar shows "Claude API" instead of the subscription name ([#11985](https://github.com/anthropics/claude-code/issues/11985)). Chat works fine.

### GitHub CLI

`GH_TOKEN` is used for GitHub CLI authentication. On container start, `run.sh` also auto-configures git user (name and email) from the GitHub account.

We recommend creating a separate GitHub account for SafeClaw so you can scope its permissions independently.
