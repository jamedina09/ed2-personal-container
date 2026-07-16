#!/usr/bin/env bash
# Convenience wrapper to run the ed2:personal podman image against a run
# directory (defaults to ed2-personal-container/EDTS_run, the downloaded UMBS test case).
#
# Usage:
#   ./ed2-personal-container/docker/run_ed2.sh [RUNDIR] [ED2IN_NAME]
#
# RUNDIR      directory containing ED2IN + input data, mounted at /data
#             (default: ed2-personal-container/EDTS_run)
# ED2IN_NAME  namelist file name inside RUNDIR (default: ED2IN)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNDIR="$(cd "${1:-${REPO_ROOT}/ed2-personal-container/EDTS_run}" && pwd)"
ED2IN_NAME="${2:-ED2IN}"

if [[ ! -f "${RUNDIR}/${ED2IN_NAME}" ]]; then
    echo "Could not find ${ED2IN_NAME} in ${RUNDIR}" >&2
    echo "Run ed2-personal-container/EDTS_run/fetch_test_data.sh first, or point this script at your own run directory." >&2
    exit 1
fi

podman run --rm --ulimit stack=-1:-1 \
    -v "${RUNDIR}:/data:Z" \
    ed2:personal -f "${ED2IN_NAME}"
