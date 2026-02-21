# SafeClaw

Sandboxed Docker container running Claude Code, accessible via a web terminal.

See [architecture.md](architecture.md) for full design details.

## Testing end to end

After making changes, rebuild and test:

```bash
./scripts/build.sh
./scripts/run.sh
```

This opens http://localhost:7681 in the browser. Verify:
1. Claude Code launches automatically with bypass permissions
2. Confirm it shows the correct model (Opus 4.6) and doesn't ask for login
3. Send a message and confirm it gets a response

## Agent type (Claude vs cursor)

Use `-a` to choose which agent runs in the terminal. Default is `claude`.

```bash
./scripts/run.sh -n                    # Claude Code (default)
./scripts/run.sh -s work -n -a cursor   # Cursor agent in this session
```

The choice is stored in the container's env (`SAFECLAW_AGENT`). Restarting the same container reuses the last agent type. The Cursor CLI is installed in the image; the binary is `agent` and is aliased as `cursor`.

## Multiple sessions

Run multiple isolated sessions with `-s`:

```bash
./scripts/run.sh -n                    # default on port 7681
./scripts/run.sh -s work -n            # safeclaw-work on next available port
./scripts/run.sh -s research -n        # safeclaw-research on next available port
```

## Mounting local projects

Use `-v` to mount a local directory into the container. Keep the same folder name inside the container for clarity:

```bash
./scripts/run.sh -s myproject -n -v /path/to/myproject:/home/sclaw/myproject
```

This mounts the project at `/home/sclaw/myproject` inside the container. Use the same folder name (not a generic "project") so it's clear which project you're working with. If the container already exists, it will be recreated with the new mount.

## Research sessions

For web research or any task requiring URL fetching, use a SafeClaw container instead of doing it directly on the host. The `-q` option sends a query directly to Claude Code inside the container:

```bash
./scripts/run.sh -s research -n -q "Research Inngest and explain how durable execution works"
```

This starts the container (or reuses an existing one) and sends the query to Claude Code running inside it.

## Dashboard

Start the dashboard to manage all sessions:

```bash
npx nodemon dashboard/server.js
```

Always use nodemon during development for auto-restart on changes.

Opens at http://localhost:7680. Shows all sessions with:
- Start/stop/delete buttons
- Live iframes of active sessions
- Auto-refreshes via Docker events (SSE)

## Conversation history and memory

Each session's data persists at `~/.config/safeclaw/sessions/<session-name>/` on the host, mounted to `/home/sclaw/.claude/projects/` in the container.

This includes:
- **Conversations:** JSONL files (one per conversation)
- **Memory:** Auto memory at `-home-sclaw/memory/MEMORY.md` (loaded into system prompt each conversation)

Rebuilding containers or restarting sessions won't affect either.

## Starting and stopping containers

Always use these methods (they handle ttyd startup):
- `./scripts/run.sh -s name -n` - create or start a session
- Dashboard start/stop buttons - manage running sessions

`run.sh` refreshes env vars from `~/.config/safeclaw/.secrets/` into the container's `/home/sclaw/.env`.

**Don't use raw `docker start`** - it won't start ttyd inside the container.

## Sending commands to the container via tmux

When sending commands to the container's tmux session with `tmux send-keys`, the message may not go through on the first Enter. If `tmux capture-pane` shows the prompt is still empty (the `❯` line has no text after it, or the text is there but hasn't been submitted), send additional Enter keys:

```bash
docker exec safeclaw-default tmux send-keys -t main Enter
docker exec safeclaw-default tmux send-keys -t main 'your command' Enter
docker exec safeclaw-default tmux capture-pane -t main -p
```

For other sessions, replace `default` with the session name (e.g., `safeclaw-work`).

Always verify with `tmux capture-pane -t main -p` that the command was actually submitted.
