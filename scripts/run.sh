#!/bin/bash
# Start/reuse container, inject auth tokens, start ttyd web terminal

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_NAME="safeclaw"
SECRETS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/safeclaw/.secrets"

# Check if image exists
if ! docker images -q safeclaw | grep -q .; then
    echo "Error: Image 'safeclaw' not found. Run ./scripts/build.sh first."
    exit 1
fi

# Check if container exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Reusing running container: $CONTAINER_NAME"
    else
        echo "Starting existing container: $CONTAINER_NAME"
        docker start "$CONTAINER_NAME" > /dev/null
    fi
else
    echo "Creating container: $CONTAINER_NAME"
    docker run -d --ipc=host --name "$CONTAINER_NAME" -p 127.0.0.1:7681:7681 safeclaw sleep infinity > /dev/null
fi

# === Claude Code token setup ===

mkdir -p "$SECRETS_DIR"

if [ ! -f "$SECRETS_DIR/claude_oauth_token" ]; then
    echo ""
    echo "=== Claude Code setup ==="
    echo ""
    echo "No Claude Code token found. Let's set one up."
    echo ""
    echo "Run this command in another terminal:"
    echo ""
    echo "  claude setup-token"
    echo ""
    echo "It will generate a long-lived OAuth token (valid for 1 year)."
    echo "Paste the token below."
    echo ""
    while true; do
        read -p "Token: " claude_token
        if [ -n "$claude_token" ]; then
            echo "$claude_token" > "$SECRETS_DIR/claude_oauth_token"
            echo "Saved to $SECRETS_DIR/claude_oauth_token"
            break
        fi
        echo "Token is required. Please run 'claude setup-token' and paste the result."
    done
fi

# === GitHub CLI token setup ===

if [ ! -f "$SECRETS_DIR/gh_token" ]; then
    echo ""
    echo "=== GitHub CLI setup ==="
    echo ""
    echo "No GitHub token found. Let's set one up."
    echo ""
    echo "We recommend creating a separate GitHub account for SafeClaw"
    echo "so you can scope its permissions independently."
    echo ""
    echo "Once logged in, run this in another terminal:"
    echo ""
    echo "  gh auth token"
    echo ""
    echo "Or create a Personal Access Token at:"
    echo "  https://github.com/settings/tokens"
    echo ""
    echo "Paste the token below."
    echo ""
    read -p "Token: " gh_token

    if [ -n "$gh_token" ]; then
        echo "$gh_token" > "$SECRETS_DIR/gh_token"
        echo "Saved to $SECRETS_DIR/gh_token"
    else
        echo "No token provided, skipping. You can set it up later by re-running this script."
    fi
fi

# Build env var flags
ENV_FLAGS=""
if [ -f "$SECRETS_DIR/claude_oauth_token" ]; then
    ENV_FLAGS="$ENV_FLAGS -e CLAUDE_CODE_OAUTH_TOKEN=$(cat "$SECRETS_DIR/claude_oauth_token")"
fi
if [ -f "$SECRETS_DIR/gh_token" ]; then
    ENV_FLAGS="$ENV_FLAGS -e GH_TOKEN=$(cat "$SECRETS_DIR/gh_token")"
fi

# Start ttyd with wrapper that passes env vars through to tmux
docker exec $ENV_FLAGS -d "$CONTAINER_NAME" \
    ttyd -W -p 7681 /home/sclaw/ttyd-wrapper.sh

echo ""
echo "SafeClaw is running at: http://localhost:7681"
echo ""
echo "To stop: docker stop $CONTAINER_NAME"

# Open in browser
if command -v open >/dev/null 2>&1; then
    open http://localhost:7681
elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open http://localhost:7681
fi
