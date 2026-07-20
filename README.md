# ed2-personal-container

Builds a podman-friendly container image for the [ED2](https://github.com/jamedina09/ED2)
ecosystem model. At the moment, it uses my forked ED2, which is the same as what is in the ED2 master branch. You can create one using your own fork version. This repo only builds and publishes the image — running
simulations happens in the sibling
[ED2_RUNS](https://github.com/jamedina09/ED2_RUNS) repo, against your own
local run directories.

## What this builds

The dockerfile in this repo is a modified version of the ED2 provided dockerfile, but fitted to my personal preferences.

A two-stage Ubuntu 22.04 image. The **build stage** compiles ED2 (via ED2's
own `ED/build/install.sh`, not a generic Makefile) using `gfortran` and
HDF5/BLAS/LAPACK dev packages from apt — this stage is large (~700 MB) since
it carries the full compiler toolchain and ED2 source tree. The **runtime
stage** is a fresh, separate base image that only installs the shared
libraries the already-compiled `ed2` binary needs to run, plus `gosu` and the
generic EDTS phenology-init data bundle — everything else (compiler, dev
headers, source) is left behind. Only the compiled binary, plus two small
host-side assets (`R-utils/` and the stock `ED2IN` template, at
`/opt/ed2_assets` — not read by `ed2` itself, but needed on the host by
consumer repos like `ED2_RUNS`), cross from the build stage into the runtime
stage. Final image: ~231 MB.

**Every version-sensitive value is a build `ARG`, not hardcoded** — the ED2
git ref, and every pinned compiler/library version. The Dockerfile's own
`ARG` defaults are just *a* version (currently commit `d971a620`), not *the*
version. The source of truth for "what versions exist and what their exact
pins are" is `versions/*.args`, one small file per release, each built via
`./build.sh` — see `CHANGELOG.md` for what's available and "Building a
different ED2 version" below for how a new one gets added.

A non-root user `ed2-user` (UID 1000, group `ed2`) owns the image-internal
data `entrypoint.sh` remaps that UID/GID to whoever runs the container (see
"How the entrypoint works" below) — this is what makes the same image work
correctly on any host, writing output owned by you rather than some
container-internal default.

## Prerequisites

- **Podman** (or Docker — every command below works identically with
  `docker` in place of `podman`). Install: <https://podman.io/docs/installation>
- macOS/Windows only (not Linux): `podman machine start` first.
- No unusual RAM/disk requirements — this build is far lighter than a
  from-source GCC-toolchain build (a few minutes, not tens of minutes), since
  it uses apt-installed `gfortran`/HDF5 rather than compiling its own.
- Compiler/library versions are pinned as build `ARG`s, with each released
  version's exact values recorded in its own `versions/*.args` file. Check
  current resolvable versions with `apt-cache policy <package>` in a fresh
  `ubuntu:22.04` container before bumping any of them — apt package versions
  age out of the mirror over time, unlike GitHub tags.

## 1. Build the image

Build using the helper script, which reads the right version's pin file and
turns it into the right `--build-arg` flags for you — run from the repo root,
naming any version listed in `versions/` (see `CHANGELOG.md` for what each
one is):

```sh
git clone <this-repo-url>
cd ed2-personal-container
./build.sh d971a620
```

This only tags the image with its own version tag (`ed2:d971a620`) — it
deliberately does **not** touch `:latest` unless you pass `--tag-latest`, so
building/testing any version (including a brand new one you're adding) can
never affect what's currently the default pull for anyone already using this
image. Decide to retag `:latest` only after a new version is fully verified
(see step 2) — that's a separate, deliberate decision, not a side effect of
building.

Equivalent to running `podman build` by hand with each pin file's values
passed as `--build-arg` — you can do that directly instead if you want to
override just one or two values ad hoc without creating a new pin file:

```sh
podman build -t ed2:experimental \
    --build-arg ED2_GIT_URL=https://github.com/<other>/ED2.git \
    --build-arg ED2_GIT_REF=some-branch \
    -f docker/Dockerfile.personal .
```

Check it built:

```sh
podman images ed2
```

## 2. Verify the build before pushing

Follow this step if you have BCI data in your local device.

Confirm the tag exists and is roughly the expected size (~187 MB — if it's
dramatically smaller, something likely failed silently mid-build):

```sh
podman images ed2
```

Then run an actual smoke test — this is what actually proves the pinned ED2
ref, compiler, and library versions work together, not just that the build
completed. This repo doesn't ship run data itself (that's what
[ED2_RUNS](https://github.com/jamedina09/ED2_RUNS) is for); the real
verification is running that repo's pipeline against your freshly built
image:

```sh
cd ../ED2_RUNS   # sibling repo, cloned alongside this one
IMAGE=localhost/ed2:d971a620 ./run_ed2.sh sites/BCI/run ED2IN-<some-experiment>
```

(See `ED2_RUNS`' own README for how to build a run directory and `ED2IN` if
you don't have one yet — its "Manual Workflow" section walks through
building shared site inputs once, then an experiment's `ED2IN`, in full.)

Success looks like `Time integration ends` in the run's log, and correctly
produced `analysis-*.h5`/`history-*.h5` output files — check their
**ownership** too (`ls -la`), not just that they exist: they should be owned
by you, not some container-internal UID. If they're not, or if the run fails
with a permission error writing into the run directory, that's the entrypoint
UID/GID remap not being invoked correctly — see "How the entrypoint works"
below; the most common cause is a caller (like an older `run_ed2.sh`) not
passing `LOCAL_UID`/`LOCAL_GID` to `podman run`.

Any *other* failure — the ED2 binary itself erroring, unexpected output
values — is a real ED2-ref/toolchain compatibility problem, not a container
plumbing issue. Stop and investigate rather than assume it's fine.

## 3. Push the image to GHCR

Pushing puts the image on the GitHub Container Registry (`ghcr.io`) so it can
be pulled from any other machine. **The image is uploaded to your GitHub
account's package namespace (`ghcr.io/<your-username>/...`) — it is not tied
to either this repo or [ED2_RUNS](https://github.com/jamedina09/ED2_RUNS).**
Push access comes from your account/token, not from repo membership.

### 3a. Create a GitHub token

GHCR does not accept your regular GitHub password for login — you need a
Personal Access Token (PAT) with package scopes.

1. Go to <https://github.com/settings/tokens> → **Tokens (classic)** →
   **Generate new token** → **Generate new token (classic)**. (GHCR's
   docker/podman login does not reliably support fine-grained tokens — use a
   classic token.)
2. Give it a descriptive name (e.g. `ghcr-ed2-personal`) and an expiration.
3. Under scopes, check **both** `write:packages` and `read:packages`.
4. Click **Generate token** and copy it immediately — GitHub only shows it
   once. Store it somewhere safe.

### 3b. Log in

```sh
podman login ghcr.io -u <your-github-username>
```

Paste the PAT as the password when prompted. If push later fails with
`permission_denied: The token provided does not match expected scopes`, the
stored token is missing `write:packages` — regenerate it with that scope
checked and `podman logout ghcr.io && podman login ghcr.io -u <username>`
again.

### 3c. Push

```sh
podman tag ed2:d971a620 ghcr.io/<your-github-username>/ed2:d971a620
podman push ghcr.io/<your-github-username>/ed2:d971a620
```

Only push `:latest` too if you actually want this version to become the new
default pull target — that's a deliberate decision, not automatic:

```sh
podman tag ed2:d971a620 ghcr.io/<your-github-username>/ed2:latest
podman push ghcr.io/<your-github-username>/ed2:latest
```

## 4. Using the image

Downloading, extracting the image's baked-in `R-utils`/`ED2IN` assets, and
running actual experiments against it are **not** this repo's job — that
entire workflow lives in the sibling
[ED2_RUNS](https://github.com/jamedina09/ED2_RUNS) repo.

See that repo's README:

- **Requirements and Installation** (pulling the image, one-time
  `./setup.sh` to extract `R-utils`/`ED2IN` — no local build needed for this)
- **Manual Workflow** / **Automated Workflow** (building a run directory,
  and the full build→run→extract→plot→catalog pipeline)

This repo's job ends at step 3 above: build, verify, and publish an image.
Everything downstream of "I have an image reference I want to use" belongs
in `ED2_RUNS`.

## How the entrypoint works

`entrypoint.sh` is what makes one image work correctly as any host's
UID/GID, ported from the same fix in the sibling ELM-FATES-PERSONAL-CONTAINER
image:

1. The container **always starts as root**, regardless of who runs it —
   there is no `USER ed2-user` instruction in the Dockerfile (on purpose:
   `usermod`/`groupmod` below require root).
2. It reads `LOCAL_UID`/`LOCAL_GID` from the environment (defaults `1000`/
   `1000`, the image's build-time values, if unset).
3. It runs `usermod -o -u "$LOCAL_UID" ed2-user` and `groupmod -o -g
   "$LOCAL_GID" ed2` to reassign the account to match. **`-o` (non-unique)
   is required** — without it, `usermod`/`groupmod` refuse to assign a
   UID/GID already claimed by another account, and macOS's default primary
   group `staff` happens to be GID 20, which collides with Ubuntu's built-in
   `dialout` group. Omitting `-o` crashes the entrypoint (`set -e`) with
   `groupmod: GID '20' already exists` and the container never starts —
   confirmed the hard way in the sibling image, applied here from the start.
4. It `chown -R`s the image-internal `/opt/ed2_common` directory — never the
   bind mount (`/data`) itself, which already has the right ownership from
   step 3 matching the host.
5. It raises the stack ulimit (ED2 segfaults early without this).
6. Finally, `exec gosu ed2-user /usr/bin/ed2 "$@"` drops privileges and runs
   the model as `ed2-user`.

Unlike the ELM-FATES image, this one has no interactive-shell use case and
nothing analogous to `podman exec` in its normal workflow — every invocation
goes through `podman run`, which always goes through the entrypoint, so there
isn't a "bypasses the entrypoint" gotcha to watch for here.

## Building a different ED2 version

The core difficulty is the same one the sibling ELM-FATES-PERSONAL-CONTAINER
repo hit: **there is usually no ready-made tag to pin to.** The fork this
Dockerfile builds from has no tags at all, and upstream's only real tag is
years stale. Don't assume a tag exists — check, and be ready to pin a commit
hash instead.

1. **Decide what you're pinning to** — a specific commit on the fork's
   `master` (the common case, since the fork otherwise floats), a different
   branch, or a different fork/repo entirely via `ED2_GIT_URL`.
2. **Check whether the compiler/library versions still need to change.**
   They usually won't (ED2's actual apt dependencies are stable across
   Ubuntu 22.04's lifetime) — but re-check with `apt-cache policy <package>`
   in a fresh `ubuntu:22.04` container rather than assuming the existing
   pins still resolve; an apt package version can age out of the mirror.
3. **Write the new pin file** at `versions/<short-sha-or-name>.args` — copy
   the format of `versions/d971a620.args`, and **write down the reasoning
   for every change**, not just the new values.
4. **Build and smoke-test it** exactly as in steps 1-2 above, through the
   real `ED2_RUNS` pipeline, not a synthetic check. This is what actually
   proves the new ED2 ref/toolchain combination works, not assumed.
5. **Add a `CHANGELOG.md` entry** documenting the new version, the same way
   as the `d971a620` entry — versions, what changed and why, verification
   performed.
6. **Push and decide about `:latest`** per step 3 above, once satisfied.
