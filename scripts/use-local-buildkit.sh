#!/bin/bash
# Use custom BuildKit with cache debugging in any project
#
# Usage:
#   1. In your project, source this script:
#      source /path/to/buildkit/scripts/use-local-buildkit.sh
#
#   2. Build your images:
#      docker buildx build -t myapp .
#
#   3. Check cache logs:
#      cache-logs
#
# Environment variables:
#   BUILDKIT_IMAGE - custom BuildKit image (default: benoittigeotlifen/buildkit-cache-debug:latest)
#   BUILDKIT_BUILDER_NAME - builder name (default: cache-debug)

BUILDER_NAME="${BUILDKIT_BUILDER_NAME:-cache-debug}"
BUILDKIT_IMAGE="${BUILDKIT_IMAGE:-benoittigeotlifen/buildkit-cache-debug:latest}"

# Create builder with custom BuildKit if it doesn't exist
setup-builder() {
    if ! docker buildx inspect "$BUILDER_NAME" &>/dev/null; then
        echo "Creating builder '$BUILDER_NAME' with image '$BUILDKIT_IMAGE'..."
        docker buildx create \
            --driver=docker-container \
            --name="$BUILDER_NAME" \
            --driver-opt image="$BUILDKIT_IMAGE" \
            --bootstrap
    else
        echo "Builder '$BUILDER_NAME' already exists"
    fi
    docker buildx use "$BUILDER_NAME"
    echo "Now using builder: $BUILDER_NAME"
}

# Reset builder (useful after rebuilding BuildKit)
reset-builder() {
    echo "Removing builder '$BUILDER_NAME'..."
    docker buildx rm "$BUILDER_NAME" 2>/dev/null
    setup-builder
}

# Show cache debugging logs
cache-logs() {
    docker logs "buildx_buildkit_${BUILDER_NAME}0" 2>&1 | grep '\[cache'
}

# Show cache logs in real-time
cache-logs-follow() {
    docker logs -f "buildx_buildkit_${BUILDER_NAME}0" 2>&1 | grep --line-buffered '\[cache'
}

# Clear builder cache
clear-cache() {
    docker buildx prune --builder="$BUILDER_NAME" -f
}

# Auto-setup on source
setup-builder

echo ""
echo "Commands available:"
echo "  cache-logs        - Show cache debugging logs"
echo "  cache-logs-follow - Follow cache logs in real-time"
echo "  reset-builder     - Recreate builder (after rebuilding BuildKit)"
echo "  clear-cache       - Clear builder cache"
