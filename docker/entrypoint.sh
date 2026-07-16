#!/usr/bin/env bash
# ED2 segfaults early in execution unless the stack size limit is raised
# (see EDTS/run-test.sh). Set it here so users don't have to remember
# --ulimit on every `podman run`.
ulimit -s unlimited 2>/dev/null

exec /usr/bin/ed2 "$@"
