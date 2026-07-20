#!/usr/bin/env bash
# Remaps ed2-user/ed2 to the host UID/GID passed in at `podman run` time
# (LOCAL_UID/LOCAL_GID), so bind-mounted run directories are writable
# regardless of which machine built or is running the image. Falls back to
# the image defaults (1000/1000) if the caller doesn't set them.
#
# ED2 also segfaults early in execution unless the stack size limit is
# raised (see EDTS/run-test.sh) - set unconditionally below.
set -e

LOCAL_UID="${LOCAL_UID:-1000}"
LOCAL_GID="${LOCAL_GID:-1000}"

CURRENT_UID="$(id -u ed2-user)"
CURRENT_GID="$(getent group ed2 | cut -d: -f3)"

# -o allows reusing a UID/GID already claimed by another account (e.g. macOS
# assigns GID 20 to "staff", which collides with Ubuntu's built-in "dialout"
# group) - without it, usermod/groupmod refuse and the container fails to
# start. Confirmed necessary the hard way in the sibling ELM-FATES image;
# applied here from the start instead of waiting to hit the same bug.
if [ "$LOCAL_GID" != "$CURRENT_GID" ]; then
    groupmod -o -g "$LOCAL_GID" ed2
fi

if [ "$LOCAL_UID" != "$CURRENT_UID" ]; then
    usermod -o -u "$LOCAL_UID" ed2-user
fi

chown -R ed2-user:ed2 /opt/ed2_common

ulimit -s unlimited 2>/dev/null

exec gosu ed2-user /usr/bin/ed2 "$@"
