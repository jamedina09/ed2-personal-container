# Changelog

Tracks which image tag on GHCR corresponds to which ED2 version and toolchain.
The image tag pushed to `ghcr.io/jamedina09/ed2` is the short commit SHA below
(also recorded as the `org.opencontainers.image.version` label on the image
itself — check with `podman inspect <image> | grep version`).

The [ED2_RUNS](https://github.com/jamedina09/ED2_RUNS) repo distributes the
built images and drives experiments against them.

## d971a620 (assets update) — 2026-07-20

Same ED2 ref/toolchain pins as the `2026-07-19` entry below (image content
changed, version identifier did not — same pattern as the sibling
ELM-FATES-PERSONAL-CONTAINER's git-identity fix).

**What changed:** `R-utils/` and the stock `ED2IN` template are now baked
into the runtime image at `/opt/ed2_assets` (previously they only existed in
the build stage). Neither is read by `ed2` itself — they exist purely for
consumer repos (`ED2_RUNS`) to `podman cp` onto the host. Before this,
extracting them required separately cloning this repo and building its
~700MB `--target build` stage locally, even though the runtime image was
already pulled from GHCR — the only reason a routine `ED2_RUNS` user ever
needed this repo checked out at all. Now a single `podman cp` against the
already-pulled runtime image is enough. Image size: ~187 MB → ~231 MB.

**Verification performed:** rebuilt (mostly cache-hit — only the new `COPY`
steps re-ran), confirmed `/opt/ed2_assets/{R-utils,ED2IN}` present with
correct `ed2-user:ed2` ownership, confirmed extracted contents are
byte-identical (`md5sum`) to what the old build-stage extraction produced,
then re-ran the full BCI smoke test end-to-end (167.4s → 156.8s, both within
normal variance) to confirm the image still runs correctly — not just that
the new files exist.

## d971a620 — 2026-07-19

- `ED2_GIT_URL=https://github.com/jamedina09/ED2.git`
- `ED2_GIT_REF=d971a62058f67c782557021f9a7397eb2492ef46` (a **commit hash**,
  not a tag — see below)
- `GFORTRAN_VERSION=4:11.2.0-1ubuntu1`
- `HDF5_DEV_VERSION` / `HDF5_RUNTIME_VERSION=1.10.7+repack-4ubuntu2`
- `BLAS_VERSION` / `LAPACK_VERSION=3.10.0-2ubuntu1`
- `LIBGOMP_VERSION=12.3.0-1ubuntu1~22.04.3`

**First pinned/versioned release.** Prior builds floated on `ED2_GIT_REF=master`
with no compiler/library version pins — this release establishes the same
discipline used in the sibling
[ELM-FATES-PERSONAL-CONTAINER](https://github.com/jamedina09/ELM-FATES-PERSONAL-CONTAINER)
repo: every version-sensitive value is a build `ARG` with a version-controlled
default, recorded in `versions/*.args`, built via `build.sh`.

**Derivation:** `jamedina09/ED2` (the fork this image builds from) has no
tags at all. Upstream `EDmodel/ED2`'s only real tag, `v.2.2.0`, is from
2020-02-08 — 295 commits and 6+ years behind current master, too stale to use
(would likely regress capabilities the `ED2_RUNS` BCI site setup already
depends on). Confirmed via the GitHub compare API that the fork's `master` is
currently identical to upstream's `master` (0 ahead, 0 behind) — no custom
patches as of this pin. So: pinned the exact commit SHA of "current master"
as of this release, the same approach used for `ELM-FATES-PERSONAL-CONTAINER`'s
`HLM_TAG` when no clean tag existed there either.

**Compiler/library versions** are pinned to whatever Ubuntu 22.04's apt repo
resolved them to at pin time (checked via `apt-cache policy <package>` in a
fresh `ubuntu:22.04` container). Unlike the ELM-FATES image (which compiles
its toolchain from source), this image installs from apt — pinning exact
package version strings is what keeps two builds of the same Dockerfile
months apart from silently getting different HDF5/BLAS/LAPACK builds.
`ca-certificates` and `git` are deliberately left unpinned (build tooling,
not part of the compiled model; `ca-certificates` specifically needs to stay
current for HTTPS fetches to keep working).

**Also in this release:**
- Added a non-root user (`ed2-user`) and `entrypoint.sh` UID/GID remap,
  ported from the sibling ELM-FATES image — the container previously ran as
  root with no cross-machine permission handling. `-o` (non-unique) is used
  on `usermod`/`groupmod` for the same reason it's needed there: macOS's
  `staff` group is GID 20, colliding with Ubuntu's built-in `dialout` group.
- Removed a redundant `COPY --from=build` hop for `entrypoint.sh` — the final
  stage now copies it directly from the build context.
- Untracked `.DS_Store`, added `.gitignore`/`.dockerignore` (neither existed
  before).

**Verification performed:** built, then smoke-tested through the full
`ED2_RUNS` pipeline (not a synthetic test) — real BCI data prep
(248,715-stem ForestGEO census, 14 years of tower meteorology), a 3-month
`E3SM_FATES_TEST`-equivalent run (`smoketest`, 2003-01-01 to 2003-03-31),
completed in 167.4s (matches `ED2_RUNS`' README's own ~165s estimate for
this configuration). Confirmed `analysis-E-*.h5`/`history-S-*.h5` output was
produced and correctly owned by the host user, not the container's internal
UID — the concrete proof the UID/GID fix works, not just that it doesn't
crash. This also surfaced and fixed a real bug: `ED2_RUNS/run_ed2.sh` didn't
pass `LOCAL_UID`/`LOCAL_GID` to `podman run`, so the first smoke-test attempt
reproduced exactly the permission-denied bug class this fix exists to
prevent (`Fortran runtime error: ... Permission denied` writing into the
bind-mounted run directory) — see `ED2_RUNS`' own `CHANGELOG.md`.
