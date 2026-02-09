#!/bin/bash
# Start/reuse container, inject auth tokens, start ttyd web terminal

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SAFECLAW_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/safeclaw"
SECRETS_DIR="$SAFECLAW_DIR/.secrets"
SESSIONS_DIR="$SAFECLAW_DIR/sessions"
SESSION_NAME=""
VOLUME_MOUNT=""
NO_OPEN=false
QUERY=""

# Parse arguments
while getopts "s:v:nq:" opt; do
    case $opt in
        s)
            SESSION_NAME="$OPTARG"
            ;;
        v)
            VOLUME_MOUNT="$OPTARG"
            ;;
        n)
            NO_OPEN=true
            ;;
        q)
            QUERY="$OPTARG"
            ;;
        *)
            echo "Usage: $0 [-s session_name] [-v /host/path:/container/path] [-n] [-q \"question\"]"
            exit 1
            ;;
    esac
done

# Set container name based on session (default to "default")
SESSION_NAME="${SESSION_NAME:-default}"
CONTAINER_NAME="safeclaw-${SESSION_NAME}"

# Find available port (starting from 7681)
find_available_port() {
    local port=7681
    while docker ps --format '{{.Ports}}' | grep -q ":${port}->"; do
        port=$((port + 1))
    done
    echo $port
}

# Get port for this container (reuse existing or find new)
get_container_port() {
    local existing_port=$(docker ps --format '{{.Names}} {{.Ports}}' | grep "^${CONTAINER_NAME} " | sed -n 's/.*:\([0-9]*\)->7681.*/\1/p')
    if [ -n "$existing_port" ]; then
        echo "$existing_port"
    else
        find_available_port
    fi
}

PORT=$(get_container_port)

# Check if image exists
if ! docker images -q safeclaw | grep -q .; then
    echo "Error: Image 'safeclaw' not found. Run ./scripts/build.sh first."
    exit 1
fi

# If volume mount requested and container exists, remove it to recreate with new mount
if [ -n "$VOLUME_MOUNT" ] && docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Volume mount requested. Removing existing container..."
    docker rm -f "$CONTAINER_NAME" > /dev/null
fi

# Check if container exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Reusing running container: $CONTAINER_NAME"
        # Restart ttyd/tmux so fresh env vars take effect
        docker exec "$CONTAINER_NAME" pkill -f ttyd 2>/dev/null
        docker exec "$CONTAINER_NAME" tmux kill-server 2>/dev/null
        sleep 1
    else
        echo "Starting existing container: $CONTAINER_NAME"
        docker start "$CONTAINER_NAME" > /dev/null
    fi
else
    echo "Creating container: $CONTAINER_NAME"

    # Create session data directory for Claude history persistence
    SESSION_DATA_DIR="$SESSIONS_DIR/$SESSION_NAME"
    mkdir -p "$SESSION_DATA_DIR"

    VOLUME_FLAGS="-v $SESSION_DATA_DIR:/home/sclaw/.claude/projects"
    if [ -n "$VOLUME_MOUNT" ]; then
        VOLUME_FLAGS="$VOLUME_FLAGS -v $VOLUME_MOUNT"
        echo "Mounting volume: $VOLUME_MOUNT"
    fi
    docker run -d --ipc=host --name "$CONTAINER_NAME" -p 127.0.0.1:${PORT}:7681 $VOLUME_FLAGS safeclaw sleep infinity > /dev/null
fi

# === Claude Code token setup ===

mkdir -p "$SECRETS_DIR"

if [ ! -f "$SECRETS_DIR/CLAUDE_CODE_OAUTH_TOKEN" ]; then
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
            echo "$claude_token" > "$SECRETS_DIR/CLAUDE_CODE_OAUTH_TOKEN"
            echo "Saved."
            break
        fi
        echo "Token is required. Please run 'claude setup-token' and paste the result."
    done
fi

# === GitHub CLI token setup ===

if [ ! -f "$SECRETS_DIR/GH_TOKEN" ]; then
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
        echo "$gh_token" > "$SECRETS_DIR/GH_TOKEN"
        echo "Saved."
    else
        echo "No token provided, skipping. You can set it up later by re-running this script."
    fi
fi

# Build env var flags from secrets (filename = env var name)
ENV_FLAGS=""
for secret_file in "$SECRETS_DIR"/*; do
    if [ -f "$secret_file" ]; then
        ENV_FLAGS="$ENV_FLAGS -e $(basename "$secret_file")=$(cat "$secret_file")"
    fi
done

# Set git config from GitHub account if logged in
if [ -f "$SECRETS_DIR/GH_TOKEN" ]; then
    docker exec $ENV_FLAGS "$CONTAINER_NAME" sh -c '
        if gh auth status >/dev/null 2>&1; then
            USER_DATA=$(gh api user 2>/dev/null)
            if [ -n "$USER_DATA" ]; then
                NAME=$(echo "$USER_DATA" | jq -r ".name // .login")
                LOGIN=$(echo "$USER_DATA" | jq -r ".login")
                EMAIL=$(echo "$USER_DATA" | jq -r ".email // empty")
                # Use noreply email if no public email
                [ -z "$EMAIL" ] && EMAIL="${LOGIN}@users.noreply.github.com"
                git config --global user.name "$NAME"
                git config --global user.email "$EMAIL"
            fi
        fi
    '
fi

# Set title based on session name
TITLE="SafeClaw - ${SESSION_NAME}"

# Start ttyd with wrapper that passes env vars through to tmux
docker exec $ENV_FLAGS -d "$CONTAINER_NAME" \
    ttyd -W -t titleFixed="$TITLE" -p 7681 /home/sclaw/ttyd-wrapper.sh

echo ""
echo "SafeClaw is running at: http://localhost:${PORT}"

# Query mode - send query to the interactive session
if [ -n "$QUERY" ]; then
    echo "Starting session and sending query..."
    # Start tmux session directly (same as ttyd-wrapper.sh does)
    docker exec $ENV_FLAGS "$CONTAINER_NAME" bash -c '
        if ! tmux has-session -t main 2>/dev/null; then
            tmux -f /dev/null new -d -s main
            tmux set -t main status off
            tmux set -t main mouse on
            while IFS="=" read -r name value; do
                tmux set-environment -t main "$name" "$value"
            done < <(env)
            tmux send-keys -t main "eval \"\$(tmux show-environment -s)\" && claude --dangerously-skip-permissions" Enter
        fi
    '
    # Wait for Claude Code to initialize
    sleep 3
    # Send the query
    docker exec "$CONTAINER_NAME" tmux send-keys -t main "$QUERY" Enter
    sleep 0.5
    docker exec "$CONTAINER_NAME" tmux send-keys -t main Enter
    echo "Query sent: $QUERY"
fi
echo ""
echo "To stop: docker stop $CONTAINER_NAME"

# Open in browser (unless -n flag)
if [ "$NO_OPEN" = false ]; then
    if command -v open >/dev/null 2>&1; then
        open "http://localhost:${PORT}"
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "http://localhost:${PORT}"
    fi
fi
