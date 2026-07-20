#!/bin/bash
# Build the image for a specific ED2 version, from its pin file in
# versions/*.args. Must be run from the repo root (build context
# requirement, same as a manual `podman build`).
#
# Usage:
#   ./build.sh d971a620
#   ./build.sh d971a620 --tag-latest   # also tag :latest
#
# By default this ONLY tags the image with its own version tag - it never
# touches :latest unless you pass --tag-latest, so building/testing a new
# version can never affect what's currently the "default" pull for anyone
# already using this image.
set -e

VERSION="$1"
ARGS_FILE="$(dirname "$0")/versions/${VERSION}.args"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <ed2-version> [--tag-latest]" >&2
    echo "Available versions:" >&2
    ls "$(dirname "$0")/versions/" | sed 's/\.args$//' | sed 's/^/  /' >&2
    exit 1
fi

if [ ! -f "$ARGS_FILE" ]; then
    echo "Error: no pin file at $ARGS_FILE" >&2
    exit 1
fi

BUILD_ARGS=()
while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    BUILD_ARGS+=(--build-arg "${key}=${value}")
done < "$ARGS_FILE"

TAGS=(-t "ed2:${VERSION}")
if [ "$2" == "--tag-latest" ]; then
    TAGS+=(-t "ed2:latest")
fi

echo "*** Building ed2:${VERSION} from ${ARGS_FILE}"
set -x
podman build "${BUILD_ARGS[@]}" "${TAGS[@]}" -f docker/Dockerfile.personal .
