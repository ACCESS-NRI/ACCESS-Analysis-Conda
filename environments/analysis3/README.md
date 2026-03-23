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
Instead, you want to modify `pixi.toml`. You can do this either by editing it directly, or by using pixi commands.

Once you've added/removed whatever you were after, proceed to solving.

### Solving the pixi environment

1. Solve the pixi environment:
```bash
pixi lock
```

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

### Exporting the pixi environment back to conda

#### Via Pixi Task

Run 
```sh
$ pixi run rebuild-env
```

#### Manually

1. Export the pixi environment to json:

```bash
pixi list --json > solved.json
```

2. Run this big chungus of a script, which uses `jq` to create a new `environment.yml` file with the solved package versions:

```bash
mv environment.yml environment.yml.bak
(
echo "name: analysis3"
echo "channels:"
echo "  - accessnri"
echo "  - conda-forge"
echo "  - nodefaults"
echo "  - rapidsai"
echo "  - pytorch"
echo "  - nvidia"
echo "dependencies:"

# Conda packages
jq -r '
.[] 
| select(.name | startswith("__") | not)
| select(.name | startswith("_") | not)
| select(.build != null)
| "  - \(.name)=\(.version)=\(.build)"
' solved.json

echo "  - pip"
echo "  - pip:"

# Pip packages
jq -r '
.[] 
| select(.name | startswith("__") | not)
| select(.name | startswith("_") | not)
| select(.build == null)
| "    - \(.name | gsub("_"; "-"))==\(.version)"
' solved.json

) > environment.yml
```

3. Submit a PR to this repo. In theory everything will build just fine. If not, ask chatGPT for help.

### Updating the environment

1. At this point, `environment.yml` is going to be an absolute nightmare, because *every* package will be pinned. So if you want to update a package,
you'll want to edit `pixi.toml` instead. The pixi docs explain how to do this.
