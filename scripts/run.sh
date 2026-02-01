#!/bin/bash
# Start/reuse container, sync credentials, enter interactively
# For cloud deployment, use env vars instead:
#   docker run -e CLAUDE_CODE_OAUTH_TOKEN=... -e GH_TOKEN=... safeclaw

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_NAME="safeclaw"

# Check if image exists
if ! docker images -q safeclaw | grep -q .; then
    echo "Error: Image 'safeclaw' not found. Run ./scripts/build.sh first."
    exit 1
fi

# Check if container exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    # Container exists - check if running
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Reusing running container: $CONTAINER_NAME"
    else
        echo "Starting existing container: $CONTAINER_NAME"
        docker start "$CONTAINER_NAME" > /dev/null
    fi
else
    # Create new container
    echo "Creating container: $CONTAINER_NAME"
    docker run -d --ipc=host --name "$CONTAINER_NAME" safeclaw sleep infinity > /dev/null
fi

# Sync config and secrets
"$SCRIPT_DIR/sync-config-and-secrets.sh" "$CONTAINER_NAME"

# Run container setup (idempotent - skips if already done)
docker exec "$CONTAINER_NAME" bash -c "curl -sL https://raw.githubusercontent.com/ykdojo/claude-code-tips/main/scripts/container-setup.sh | bash"

# Attach interactively
echo "Entering container..."
docker exec -it "$CONTAINER_NAME" /bin/bash
