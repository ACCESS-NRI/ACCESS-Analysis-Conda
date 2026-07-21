# How to solve the conda environment with pixi


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
