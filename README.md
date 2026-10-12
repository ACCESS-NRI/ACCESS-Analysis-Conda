# ACCESS-MED Containerised Conda Environment

## Overview

The ACCESS-MED Containerised Conda environment is an approach to deploying and maintaining large conda environmnents while reducing inode usage and increasing performance. It takes advantage of `singularity`'s ability to manage overlay and `squashfs` filesystems. Each conda environment is consolidated into its own squashfs file, and then one or more of these squashfs environments is loaded using components of the environment.

This documentation deals with the installation of the ACCESS Analysis Containerised Conda environments.

## Installation requirements

The following packages are required
* Sylabs SingularityCE `>=3.7.0`
* `squashfs-tools`
* `bash >= 4.0`
* `GNU tar` (requires `--acls` extension)
* `rsync`

## Installation instructions

1) Fork the [code repository](https://github.com/coecms/cms-conda-singularity) and clone the forked repository onto the target system.
2) Construct the container. Modify the `container/container.def` with symlinks and directories matching the base operating system image of the target system.
3) Modify `scripts/install_config.sh` and `scripts/launcher_conf.sh` with appropriate settings for your system.
4) Modify the `--bind` argument to `${SINGULARITY_BINARY_PATH}` in `scripts/launcher.sh` to bind in all the necessary components of your target system's operating system image.
5) Modify `.github/workflows/build_and_test.yml` and `.github/workflows/deploy.yml` with appropriate settings for the target system.
6) Initiate a build job by creating a merge request on the forked repository.

## Update Instructions

When a build job is submitted it will modify the conda environment given by `${ENVIRONMENT}/${VERSION_TO_MODIFY}` in `scripts/install_config.sh`. The contents of this environment is determined by `scripts/environment.yml`. By default, the `main` branch is protected, any updates to the production environment must be performed through a merge request. Create a branch, modify the `environment.yml` file (e.g. add a new package), commit and push the branch, then create a merge request. The merge will be blocked until the `build` and `test` jobs have completed successfully. These jobs are performed in temporary locations, and do not affect the production environment while running. Once those steps have been completed, the branch can be merged and the `deploy` job will run.

## Retiring old analysis3 versions

After a successful `analysis3` deployment, `scripts/retire_environments.py` keeps
the six newest dated SquashFS versions. Versions listed in
`environments/analysis3/retention.json` under `pinned` are kept in addition to
those six. Use full names such as `analysis3-25.09`. The just-deployed version,
configured stable/unstable versions, and any version still referenced by an
analysis3 alias are also protected. Other environments are unaffected.

The script moves each retired version's public SquashFS, environment link,
module files, and wrapper directory to
`/g/data/xp65/admin/med_conda/admin/retired-environments/<version>/`.
It does not purge that archive. To inspect the plan without moving anything:

```bash
python3 scripts/retire_environments.py \
  --base /g/data/xp65/public \
  --admin /g/data/xp65/admin/med_conda/admin \
  --environment analysis3 \
  --config environments/analysis3/retention.json
```

Deployment removes unrelated version links and module files from the staged
tar before rsync. This prevents a build staged before retirement from
recreating those entries. The deployed SquashFS files are already excluded
from the tar. A failed rsync now stops deployment before the image or retention
step is run.

## Instructions to activate environment in a JupyterLab instance on [ARE](https://are.nci.org.au/)

Set the following:
* Under `Advanced options > Module directories` insert: `/g/data/xp65/public/modules`
* Under `Advanced options > Modules` insert: `conda/analysis3`
