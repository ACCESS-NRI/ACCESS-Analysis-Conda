# How to solve the conda environment with pixi

## Monthly analysis3 release PR

The [monthly workflow](../../.github/workflows/monthly-analysis3-pr.yml) runs at
16:17 Australia/Brisbane time on the 28th through 31st of each month. Its first
successful run opens a PR for the following month's `analysis3-YY.MM`. Later
runs leave that PR alone. You can also run **Prepare monthly analysis3 PR** from
GitHub Actions at any time; the optional `target_version` input accepts `YY.MM`.

The PR advances `VERSION_TO_MODIFY` and `UNSTABLE_VERSION` to the new month,
promotes the current version to `STABLE_VERSION`, runs `pixi update --no-install`
within the existing `pixi.toml` constraints, and regenerates `environment.yml`
from the refreshed lock. The workflow does not merge or deploy. The existing PR
workflow builds and stages the environment on Gadi; merging starts deployment
through the push-to-main workflow. The PR test job is currently disabled, so
review the package diff and Gadi build result before merging.

Before enabling the workflow, install a GitHub App on this repository with
**Contents: read and write** and **Pull requests: read and write** permissions.
Set repository variable `ANALYSIS3_PR_APP_CLIENT_ID` to its client ID and
repository secret `ANALYSIS3_PR_APP_PRIVATE_KEY` to its private key. The workflow
creates a short-lived installation token after resolving packages. The App
opens the PR, so you can approve it, and its PR event starts the existing build
without a separate workflow approval. A PR created with the built-in
`GITHUB_TOKEN` would require a separate approval to start its workflows.

The scheduled workflow only runs once this workflow file is on the default
branch. For an immediate release PR, use the manual trigger after merging this
workflow. If a monthly solve fails, the next scheduled run retries; you can
also rerun it manually after adjusting `pixi.toml` or the repository token.


### Importing a conda environment into pixi 

> [!IMPORTANT]
> This should only be necessary to generate a pixi.toml. If it already exists, skip this section

1. Install pixi, if you don't already have it.

2. Import the conda environment into a pixi project:
```bash

pixi init
pixi import environment.yml --format=conda-env
```

*You now have a pixi project, which you can solve. Pixi uses the `rattler` solver, which is apparently quite a lot better than `mamba` (N.B Wolf Vollprecht wrote both, and I think he's focussing primarily on `rattler` now).*

### Updating the pixi environment

Do not directly modify `environment.yml` - we are going to totally rebuild it.
Instead, you want to modify `pixi.toml`.

You can either:

- edit `pixi.toml` directly, or
- use pixi commands such as:

```bash
pixi add <package>
pixi remove <package>
```

If you need to target a specific dependency group or channel, adjust the command accordingly and let pixi update `pixi.toml` for you.

Once you've added/removed whatever you were after, rebuild the environment.

### Rebuilding the conda environment from pixi

Once you've updated `pixi.toml`, use the task:

```bash
pixi run rebuild-env
```

That task handles the lock/update flow and regenerates `environment.yml` for you.

On macOS, add `--as-is`:

```bash
pixi run --as-is rebuild-env
```

The workspace only targets `linux-64`, so a plain `pixi run` fails with `unsupported-platform`
when it tries to activate the environment. `--as-is` skips that activation; the task itself only
needs the `pixi` binary and `grep`, and it renders `linux-64` explicitly, so the output is
byte-identical to a Linux run.

If you wanted to use pixi shell at this point, instead of creating a pixi environment, you could do:
```bash
pixi shell
```

You can verify package versions in the pixi environment with:
```bash
pixi run python
```
```python
import blah_package
blah.__version__
```
or however you might want to do it.

Then submit a PR to this repo. In theory everything will build just fine. If not, ask chatGPT for help.

### Updating the environment

1. At this point, `environment.yml` is going to be an absolute nightmare, because *every* package will be pinned. So if you want to update a package,
you'll want to edit `pixi.toml` instead. The pixi docs explain how to do this.
