# ed2-personal-container

Podman-friendly container image for running the [ED2](https://github.com/jamedina09/ED2)
ecosystem model. This repo's only job is **building the image** — actually
running the model happens elsewhere, against whatever local run directory
you point it at (e.g. `/Users/medinaja/ED2_RUNS`).

- `docker/Dockerfile.personal` — builds the image. Clones ED2 source from
  GitHub itself during the build (see `ED2_GIT_URL`/`ED2_GIT_REF` build
  args below), so it does **not** need a local ED2 checkout to build from.
- `entrypoint.sh` — raises the stack ulimit (ED2 segfaults early without
  this) before exec-ing the `ed2` binary. Lives here because the
  Dockerfile `COPY`s it into the image at build time — it's a build
  dependency, not something you run directly.

There is deliberately no run script in this repo — see [Run it against
local data](#2-run-it-against-local-data) below.

## Prerequisites

- [podman](https://podman.io/) installed, with `podman machine` running
  (macOS/Windows only; not needed on Linux):

  ```sh
  podman machine start
  ```

## 1. Build the container

Build from the repo root (the build context must be the repo root, so
`entrypoint.sh` is available to `COPY`):

```sh
podman build -t ed2:personal -f docker/Dockerfile.personal .
```

This clones `jamedina09/ED2` at the `master` branch inside the build and
compiles it — no local ED2 source needed. Build a pinned/versioned image
instead of `master` with `--build-arg`:

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

### Extracting `R-utils/` and the `ED2IN` template (no git checkout needed)

Some data-prep pipelines (e.g. the BCI one below) need the ED2 lab's
`R-utils/*.r` physics/allometry functions and the `ED/run/ED2IN` namelist
template — both live inside the same ED2 source tree the Dockerfile
already clones, but neither ships in the final runtime image. Rather than
doing a separate `git clone` of ED2 on the host, pull them straight out of
the build stage:

```sh
podman build --target build -t ed2:build -f docker/Dockerfile.personal .

podman run --rm -v /path/to/your/run/workspace:/out:Z ed2:build sh -c "
  cp -r /ED2/R-utils /out/R-utils
  mkdir -p /out/ED/run
  cp /ED2/ED/run/ED2IN /out/ED/run/ED2IN
"
```

This gives you plain files on the host with no `.git` anywhere — handy
when the run workspace (like `ED2_RUNS`) isn't itself a git repo.

## 2. Run it against local data

The container expects a **run directory** containing an `ED2IN` namelist
plus whatever met/soil/vegetation input files that `ED2IN` points at,
bind-mounted at `/data`:

```sh
podman run --rm --ulimit stack=-1:-1 \
    -v <RUNDIR>:/data:Z \
    ed2:personal -f ED2IN
```

Paths inside `ED2IN` (met driver dir, output prefixes, etc.) must be
relative to `/data`, since that's what the container sees — not the
absolute host path of `RUNDIR`.

Running lives outside this repo entirely — this repo only builds
`ed2:personal`; it doesn't know or care where your run directories are.
A small `run_ed2.sh` wrapper (bind-mounts `RUNDIR` at `/data` and runs the
command above) is a convenient, fully portable copy to keep alongside
your run data instead of in here:

```sh
#!/usr/bin/env bash
set -euo pipefail
RUNDIR="$(cd "$1" && pwd)"
ED2IN_NAME="${2:-ED2IN}"
podman run --rm --ulimit stack=-1:-1 \
    -v "${RUNDIR}:/data:Z" \
    ed2:personal -f "${ED2IN_NAME}"
```

### Example: running the BCI data from `/Users/medinaja/ED2_RUNS`

`/Users/medinaja/ED2_RUNS` is a self-contained workspace, independent of
this repo, for a BCI (Barro Colorado Island) single-point run driven by
real site data (ForestGEO census + QA/QC'd tower met):

```text
ED2_RUNS/
├── run_ed2.sh                  # the wrapper script above
├── .ed2_repo_root               # empty marker file the BCI R scripts use
│                                 # to find this workspace's root (instead of .git)
├── R-utils/                     # ED2 lab physics/allometry functions (extracted from ed2:build, see above)
├── ED/run/ED2IN                 # ED2IN template (extracted from ed2:build, see above)
├── ED2_Support_Files-master/    # site-processing driver scripts (fetched separately)
└── BCI/
    ├── raw_data/                 # real source data: met CSVs, ForestGEO census, soil texture
    ├── run/                      # built run directory: ED2IN, met/, init/ (created by the scripts below)
    └── R/
        ├── data_preparation/
        │   ├── evaluate_bci_data.R    # optional: sanity-check the raw data
        │   └── build_bci_datasets.R   # builds met driver, soil texture, vegetation init → BCI/run/
        ├── model_runs/
        │   └── build_bci_ed2in.R      # builds the ED2IN namelist → BCI/run/ED2IN
        └── output_preparation/
            ├── extract_bci_output.R   # reads analysis-E-*.h5 output into a tidy data.table
            └── plot_bci_output.R      # plots it with ggplot2
```

Requires R plus `PEcAn.ED2`, `ncdf4`, `hdf5r`, `data.table`, `chron`,
`ggplot2` on the host — only the actual `ed2` model run happens inside the
container.

```sh
cd /Users/medinaja/ED2_RUNS

Rscript BCI/R/data_preparation/build_bci_datasets.R   # → BCI/run/{met,init}
Rscript BCI/R/model_runs/build_bci_ed2in.R             # → BCI/run/ED2IN

./run_ed2.sh BCI/run
```

Then post-process the output:

```sh
Rscript BCI/R/output_preparation/extract_bci_output.R
Rscript BCI/R/output_preparation/plot_bci_output.R
```

The same pattern applies to any other site: build (or hand-write) an
`ED2IN` + inputs directory, then point `run_ed2.sh` (or a plain `podman
run`) at it.
