#!/bin/bash
# Kill ttyd + tmux and restart the web terminal

SECRETS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/safeclaw/.secrets"
SESSION_NAME=""

# Parse arguments
while getopts "s:" opt; do
    case $opt in
        s)
            SESSION_NAME="$OPTARG"
            ;;
        *)
            echo "Usage: $0 [-s session_name]"
            exit 1
            ;;
    esac
done

# Set container name based on session (default to "default")
SESSION_NAME="${SESSION_NAME:-default}"
CONTAINER_NAME="safeclaw-${SESSION_NAME}"
TITLE="SafeClaw - ${SESSION_NAME}"

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Container '$CONTAINER_NAME' is not running. Use ./scripts/run.sh instead."
    exit 1
fi

# Get the port this container is using
PORT=$(docker ps --format '{{.Names}} {{.Ports}}' | grep "^${CONTAINER_NAME} " | sed -n 's/.*:\([0-9]*\)->7681.*/\1/p')
[ -z "$PORT" ] && PORT=7681

echo "Restarting web terminal..."
docker exec "$CONTAINER_NAME" pkill -f ttyd
docker exec "$CONTAINER_NAME" tmux kill-server 2>/dev/null

sleep 1

# Build env var flags from all secrets (filename = env var name)
ENV_FLAGS=""
if [ -d "$SECRETS_DIR" ]; then
    for secret_file in "$SECRETS_DIR"/*; do
        [ -f "$secret_file" ] || continue
        secret_name=$(basename "$secret_file")
        ENV_FLAGS="$ENV_FLAGS -e $secret_name=$(cat "$secret_file")"
    done
fi

docker exec $ENV_FLAGS -d "$CONTAINER_NAME" \
    ttyd -W -t titleFixed="$TITLE" -p 7681 /home/sclaw/ttyd-wrapper.sh

echo "SafeClaw is running at: http://localhost:${PORT}"

if command -v open >/dev/null 2>&1; then
    open "http://localhost:${PORT}"
elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "http://localhost:${PORT}"
fi
