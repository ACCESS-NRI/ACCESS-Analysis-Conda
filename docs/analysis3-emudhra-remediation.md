# analysis3 eMudhra remediation: blocked draft

**Do not merge or deploy this change yet.** The required security constraints and
validation are implemented, but the complete environment cannot currently be
solved with the existing package constraints. Neither a corrected `pixi.lock` nor
a corrected `environment.yml` has been generated. Both generated files are left
unchanged rather than hand-editing package records or claiming a partial update
is a complete fix. The new PR security gate fails on them before any Gadi setup
or build can run.

## Baseline and scope

Reviewed main at `e7ab784ec1bf5b88cb45e0120f371f5072dc4967` (2026-11-03), on
2026-11-06. `config.sh` identifies `VERSION_TO_MODIFY=26.11`,
`UNSTABLE_VERSION=26.11`, and `STABLE_VERSION=26.10`. These are aliases and one
build target, not two independent Pixi environments. This PR leaves all three
values unchanged.

| Package | Current lock/export | Required floor |
| --- | --- | --- |
| Python | 3.12.13 | 3.12.16, remain below 3.13 |
| pip | 26.1.2 | 26.2.2 |
| conda | 26.5.3 | 26.9.4 |
| certifi | 2026.10.23 | 2026.10.19 |
| ca-certificates (conda-forge) | 2026.10.23 | 2026.10.19 |
| virtualenv | 20.39.0 | 21.14.12 |

The [Python Security Response Team announcement](https://discuss.python.org/t/information-for-python-users-regarding-emudhra-emsign-ca-certificate-security-incident/109576/1)
specifies the Python, pip, virtualenv and certificate fixes. Independently
upgrading certifi does not update pip's private bundle. Optional uv and sigstore
are absent from this lock; the guard checks their current advisory floors
(0.13.6 and 4.5.1) if they are introduced.

The [conda ecosystem advisory](https://conda.org/blog/2026-10-21-emudhra-security-updates/)
requires updating each environment's CA packages and Pixi itself. All Pixi setup
steps now pin 0.82.1 and the workspace requires at least that version. Gadi's build
and deployment scripts use a separately installed Micromamba rather than Pixi;
its actual executable and host trust configuration cannot be audited here.

Mamba 2.0.8, libmamba 2.0.8, libmambapy 2.0.8,
conda-libmamba-solver 26.6.0 and conda-pypi 0.11.0 are installed. Their relevant
HTTP clients use the environment CA packages; the explicit floors protect those
paths without an unrelated Mamba library migration. No Mamba/solver build update
is claimed. CA metadata rebuilds and repodata hotfixes alone do not change an
installed bundle.

Also present: py-rattler 0.25.0 and conda-rattler-solver 0.1.1. The advisory
identifies py-rattler 0.28.0 as fixed, but warns about solver compatibility.
This locked solver requires py-rattler below 0.26. Its conda download path uses
conda's CA configuration; direct py-rattler TLS use remains a separate unresolved
exposure. An administrator must select and test a compatible solver/py-rattler
combination rather than updating that library independently.

## Why regeneration is blocked

Both Pixi 0.82.1 (the CI version) and local Pixi 0.84.1 fail the complete solve,
including with the existing `CONDA_OVERRIDE_CUDA=12` setting. A Python-only probe
also fails, so the Python incompatibility is independent of the virtualenv floor.

The available conda-forge linux-64 Python 3.12.16 build is
`h5f976f7_0_cpython`. Its metadata requires `libsqlite >=3.54.1` and a separate
libpython package. The candidate libsqlite builds either require ICU 78.3/79.1 or
constrain ICU to `<0.0a0` (the build without ICU). The current environment has ICU
75.1, required by several existing scientific/graphics/R packages. Pixi reports
no solution with the current manifest, including its preserved package pins.
This cannot be resolved by merely updating the interpreter record in the lock.

There is a second concrete compatibility constraint: the currently locked
conda-lock 4.0.2 requires `virtualenv >=20.26.6,<21.0.0`. A fresh minimal solve of
conda-lock 4.0.2 plus virtualenv >=21.14.12 fails. Keeping the old virtualenv would
retain its affected seeded packaging tools. The latest conda-lock package
metadata inspected (4.0.5) still has the same upper bound.

The normal generation commands were attempted:

```bash
cd environments/analysis3
CONDA_OVERRIDE_CUDA=12 pixi lock --no-install
CONDA_OVERRIDE_CUDA=12 pixi run --as-is rebuild-env
```

The latter stops at its `ensure-locked` prerequisite. It does not produce a new
export. Exporting the *existing* lock using the task's export/filter command
reproduces the committed `environment.yml` byte-for-byte; that checks the old
export only and is not a successful remediation.

**Package comparison:** no package versions, builds, URLs or checksums changed
in the committed lock or export. There are zero unrelated package changes.
CUDA, OpenMPI 5.0.8, UCX 1.18.1, MPI-enabled HDF5/netCDF, scientific packages and
ACCESS-NRI packages retain their original records. No solver constraints were
relaxed to force a broad upgrade.

## Checks added and results

The standard-library `scripts/check_analysis3_security.py` checks final pinned
versions in the generated export, rejects missing required packages, checks
optional affected tools, and enforces Python 3.12. Its installed mode reads the
actual interpreter/distributions and conda metadata, then checks
`pip._vendor.certifi` separately.

The existing PR workflow calls a reusable validation job before Gadi setup. It
checks the export, Pixi lock consistency and exact export reproducibility. The
monthly workflow reuses the same version guard after generation and before
committing. The analysis3 build hook checks installed versions and runs the
offline TLS tests before packaging, even while the normal Gadi PR test job is
disabled. No new scanning framework or environment dependency is added.

`scripts/test_analysis3_security.py` uses existing pytest/cryptography packages
and an in-memory TLS handshake based on
[CPython's regression test](https://github.com/python/cpython/pull/160042).
Ephemeral local certificates cover all eight compromised public keys and a
random-key positive control. No sockets, external test hosts, production keys,
or changes to system trust stores are used. Rejection must be verification code
28, not an unrelated expiration or hostname error.

| Validation | Result |
| --- | --- |
| `python3 -m unittest discover -s tests -v` | PASS: 10 tests, including existing monthly rollover tests |
| Existing broken-channel declaration check | PASS |
| Shell syntax for the modified build hook; `git diff --check` | PASS |
| Existing lock exported with the existing Pixi command | PASS: byte-identical to existing environment.yml |
| Proposed complete lock solve, Pixi 0.82.1 and 0.84.1 | FAIL: dependency incompatibility; no corrected lock produced |
| Existing `rebuild-env` task with the new constraints | FAIL at lock prerequisite |
| Security guard against the committed export | Expected FAIL: Python, pip, conda and virtualenv are below floors |
| Isolated patched runtime security tests | PASS: 10 tests, Python 3.12.16, pip 26.2.2, conda 26.9.4, virtualenv 21.14.12 |
| Pip's vendored certifi in that isolated runtime | PASS: 2026.10.19; standalone certifi and CA package are 2026.10.23 |
| Python 3.12.13 negative control | Expected FAIL: all 8 compromised-key cases; the random-key control passes |
| Advisory's public test chains against 3 isolated-runtime bundles | PASS: 48 offline checks (16 chains including rollover cases, each against certifi, pip's vendored bundle and ssl/cacert.pem); all reject with missing issuer |
| Full candidate analysis3 installation and scientific smoke tests | NOT RUN: no solvable candidate; NumPy, xarray, Iris, netCDF4, mpi4py and ACCESS-NRI runtime compatibility remains unverified |
| Gadi PBS/Singularity build, host MPI/UCX replacements, GPU/multi-rank tests, exhaustive repository import suite | NOT RUN: Gadi context unavailable; no remote build or deployment manually invoked |

The isolated runtimes are test harnesses, not analysis3 builds. Their results must
not be reported as full-environment compatibility results. The existing Gadi
test workflow is disabled in normal PRs; the manual workflow includes deployment
and must not be used as a harmless test-only command.

## Administrator decisions and stable backport

1. Obtain a trusted Python 3.12.16+ conda build compatible with the existing
   dependency graph, or approve a concrete, separately reviewed library migration
   after inspecting its package diff. Keep Python below 3.13. Resolve the
   conda-lock/virtualenv constraint with compatible package metadata/builds or an
   explicitly reviewed separation of packaging tools. Resolve direct py-rattler
   TLS use as above. Do not weaken the security floors.
2. Once those package decisions are resolved, regenerate with the existing Pixi
   task, compare every version/build against the baseline, and pass the new
   checks. Run the scientific smoke tests and existing Gadi validation against the
   staged candidate, including host OpenMPI/UCX and ACCESS-NRI customisations.
3. Backport from the actual deployed 26.10 package manifest, verified read-only
   by an administrator against its build provenance. The last main revision
   before the 26.11 rollover is `7ac8f59711db6eec54bd5dae7de0dbc36c22bddb`.
   It is a candidate source baseline, not proof of the live image's contents.
   The similarly named `analysis3-26.10` branch ends at
   `a51b0d7b2b3ef505d83b4ccedd53643b1563a5e4` (2026-09-28) and omits later October
   package changes; do not assume it is the deployed baseline.
4. In that pre-rollover source, Python/pip/conda/virtualenv have the same old
   versions, while certifi and ca-certificates are **2026.6.17** and access-moppy
   is **1.8.5**. Thus a stable backport must also update both CA packages and keep
   its original ACCESS/science versions. Do not copy the 26.11 lock (which includes
   access-moppy 1.9.0) over it. Apply only the constraints, checks and required
   dependency changes on a separate baseline and compare all changes anew.
5. The current workflow has one build target and shared staging names, and merge
   to main automatically deploys previously staged files. It has no safe stable
   backport mode with isolated staging and an explicit deployment approval.
   An administrator must approve a build-only backport procedure with a distinct
   staging destination/artifact name, verify it, and separately approve any
   replacement of the existing 26.10 SquashFS. Document/implement that procedure
   in a separate deployment change; do not retarget main or invoke the manual
   build-test-deploy workflow speculatively.
6. Leave stable=26.10 and development=26.11. Do not promote 26.11 as a shortcut.
   Any SquashFS replacement, module-alias change, or deployment requires separate
   administrator approval. Existing user virtual environments, host CA stores,
   custom CA overrides and external package-manager binaries require separate
   auditing; a new analysis3 image does not update them.

No production environment, SquashFS, module alias or deployment workflow has been
modified by this work. Keep this PR in draft until the full lock/export and Gadi
validation gaps above are resolved, then obtain approval before merging because
merge triggers deployment.
