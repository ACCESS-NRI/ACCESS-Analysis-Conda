# ACCESS-MED Containerised Conda Environment

## Overview

The ACCESS-MED Containerised Conda environment is an approach to deploying and maintaining large conda environmnents while reducing inode usage and increasing performance. It takes advantage of `singularity`'s ability to manage overlay and `squashfs` filesystems. Each conda environment is consolidated into its own squashfs file, and then one or more of these squashfs environments is loaded using components of the environment.

This documentation deals with the installation of the CMS Containerised Conda environments, for more details on usage and the motivation behind this set up, see the [Conda hh5 environment setup page on the CMS Wiki](https://climate-cms.org/cms-wiki/resources/resources-conda-setup.html). If you're experiencing an issue with the environment installed on Gadi, please submit an issue [here](https://github.com/coecms/cms-conda-singularity/issues) or email cws_help@nci.org.au.

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

For other operations, see the 'Maintenance' section of the [Conda hh5 environment setup page on the CMS Wiki](https://climate-cms.org/cms-wiki/resources/resources-conda-setup.html).

## Instructions to activate environment in a JupyterLab instance on [ARE](https://are.nci.org.au/)

Set the following:
* Under `Advanced options > Module directories` insert: `/g/data/xp65/public/modules`
* Under `Advanced options > Modules` insert: `conda/access-med`
