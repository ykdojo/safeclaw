# SafeClaw

The easiest way to run Claude Code in a Docker container. Secure, cloud-ready, with sensible defaults.

See [architecture.md](architecture.md) for design details.

## Why a container?

- **Isolated** - Claude Code runs with bypass permissions, but can't touch your host machine. A lightweight alternative to a full VM.
- **Portable** - Works on any machine with Docker (or Podman). Same environment everywhere.
- **Cloud-ready** - Auth via environment variables. Deploy anywhere by setting `CLAUDE_CODE_OAUTH_TOKEN` and `GH_TOKEN`.

## Quick start

```bash
# Build image (once, or after changes)
./scripts/build.sh

# Start container and web terminal
./scripts/run.sh

# To mount a local project (host_path:container_path)
./scripts/run.sh -v ~/myproject:/home/sclaw/myproject
```

On first run, `run.sh` will prompt you to set up authentication tokens. It then starts a web terminal at http://localhost:7681 and opens it in your browser.

## What's included

- Ubuntu 24.04
- Node.js 24 (LTS)
- Claude Code 2.1.19 (pinned, with optimized system prompt - ~45KB smaller)
- GitHub CLI with auto-configured git user
- Playwright MCP with Chromium
- Gemini CLI 0.26.0 (optional - requires API key)
- Slack read-only skill and tool (optional - requires token)
- DX plugin, custom status line, shell aliases
- ttyd web terminal + tmux

## Authentication

Tokens are stored in `~/.config/safeclaw/.secrets/` and injected as env vars on each run. The filename becomes the env var name.

| File | How to generate |
|------|-----------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | `claude setup-token` (valid 1 year) |
| `GH_TOKEN` | `gh auth token` or create a PAT at github.com/settings/tokens |

You can add any additional secrets by creating files in the `.secrets/` directory. For example, `SLACK_TOKEN` becomes the `SLACK_TOKEN` env var.

## Optional integrations

- `./scripts/setup-gemini.sh` - Add Gemini CLI access
- `./scripts/setup-slack.sh` - Add Slack read access

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/build.sh` | Build the Docker image and remove old container |
| `scripts/run.sh` | Start/reuse container, inject auth, start ttyd on port 7681. Use `-v` to mount a volume. |
| `scripts/restart.sh` | Kill and restart the web terminal (ttyd + tmux) |
| `scripts/setup-gemini.sh` | Set up Gemini CLI (optional) |
| `scripts/setup-slack.sh` | Set up Slack integration (optional) |
