# SafeClaw

Safety-first personal AI assistant. All execution happens in Docker - no host access.

See [architecture.md](architecture.md) for design details.

## Quick start

```bash
# Build image (once, or after changes)
./scripts/build.sh

# Start container and web terminal
./scripts/run.sh
```

On first run, `run.sh` will prompt you to set up authentication tokens. It then starts a web terminal at http://localhost:7681 and opens it in your browser.

## What's included

- Ubuntu 24.04
- Node.js 24 (LTS)
- Claude Code 2.1.19
- GitHub CLI
- Playwright MCP with Chromium
- DX plugin, status line, aliases
- ttyd web terminal + tmux

## Authentication

Tokens are stored on the host in `~/.config/safeclaw/.secrets/` and injected as env vars on each run.

| Token file | Env var | How to generate |
|------------|---------|-----------------|
| `claude_oauth_token` | `CLAUDE_CODE_OAUTH_TOKEN` | `claude setup-token` (valid 1 year) |
| `gh_token` | `GH_TOKEN` | `gh auth token` or create a PAT at github.com/settings/tokens |

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/build.sh` | Build the Docker image and remove old container |
| `scripts/run.sh` | Start/reuse container, inject auth, start ttyd on port 7681 |
| `scripts/restart.sh` | Kill and restart the web terminal (ttyd + tmux) |
