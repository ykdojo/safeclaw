#!/bin/bash
# Start/reuse container, set up auth tokens, enter interactively
# For cloud deployment, pass env vars directly:
#   docker run -e CLAUDE_CODE_OAUTH_TOKEN=... -e GH_TOKEN=... safeclaw

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
    docker run -d --ipc=host --name "$CONTAINER_NAME" safeclaw sleep infinity > /dev/null
fi

mkdir -p "$SECRETS_DIR"

# === Claude Code token setup ===

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
    read -p "Token: " claude_token

    if [ -n "$claude_token" ]; then
        echo "$claude_token" > "$SECRETS_DIR/claude_oauth_token"
        echo "Saved to $SECRETS_DIR/claude_oauth_token"
    else
        echo "No token provided, skipping. You can set it up later by re-running this script."
    fi
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

# Build env var flags for docker exec
ENV_FLAGS=""
if [ -f "$SECRETS_DIR/claude_oauth_token" ]; then
    ENV_FLAGS="$ENV_FLAGS -e CLAUDE_CODE_OAUTH_TOKEN=$(cat "$SECRETS_DIR/claude_oauth_token")"
fi
if [ -f "$SECRETS_DIR/gh_token" ]; then
    ENV_FLAGS="$ENV_FLAGS -e GH_TOKEN=$(cat "$SECRETS_DIR/gh_token")"
fi

# Attach interactively
echo ""
echo "Entering container..."
docker exec $ENV_FLAGS -it "$CONTAINER_NAME" /bin/bash
