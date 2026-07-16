# ed2-personal-container

Builds a podman-friendly container image for the [ED2](https://github.com/jamedina09/ED2)
ecosystem model. This repo only builds the image — running simulations
happens elsewhere, against your own local run directories.

- `docker/Dockerfile.personal` — builds the image. Clones ED2 source from
  GitHub itself during the build (see `ED2_GIT_URL`/`ED2_GIT_REF` below),
  so no local ED2 checkout is needed to build from.
- `entrypoint.sh` — raises the stack ulimit (ED2 segfaults early without
  this) before exec-ing the `ed2` binary. `COPY`'d into the image at build
  time.

## Prerequisites

[podman](https://podman.io/) installed, with `podman machine` running
(macOS/Windows only; not needed on Linux):

```sh
podman machine start
```

## Build the image

Build from the repo root (the build context must be the repo root, so
`entrypoint.sh` is available to `COPY`):

```sh
podman build -t ed2:personal -f docker/Dockerfile.personal .
```

Build a pinned/versioned image instead of `master`:

```sh
# Pin to a tag, branch, or exact commit SHA
podman build -t ed2:v1.0 --build-arg ED2_GIT_REF=v1.0 \
    -f docker/Dockerfile.personal .

# Build from a different fork/branch entirely
podman build -t ed2:experimental \
    --build-arg ED2_GIT_URL=https://github.com/<other>/ED2.git \
    --build-arg ED2_GIT_REF=some-branch \
    -f docker/Dockerfile.personal .
```

Check it built:

```sh
podman images ed2:personal
```

### Publish it to GHCR (GitHub Container Registry)

```sh
podman login ghcr.io -u <your-github-username>   # needs a PAT with write:packages
podman tag ed2:personal ghcr.io/<your-github-username>/ed2:personal
podman push ghcr.io/<your-github-username>/ed2:personal
```

On another machine, skip the build entirely:

```sh
podman pull ghcr.io/<your-github-username>/ed2:personal
podman tag ghcr.io/<your-github-username>/ed2:personal ed2:personal
```

## What's needed to run a simulation

Running is not done from this repo. To run a simulation you need,
somewhere else on disk:

- A **run directory** containing an `ED2IN` namelist plus whatever
  met/soil/vegetation input files it points at. Paths inside `ED2IN` must
  be relative (they'll be seen at `/data` inside the container, not your
  host path).
- The image built above (`ed2:personal`).

Then run it:

```sh
podman run --rm --ulimit stack=-1:-1 \
    -v /path/to/your/rundir:/data:Z \
    ed2:personal -f ED2IN
```
