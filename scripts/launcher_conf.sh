### Subject to change
export SINGULARITY_BINARY_PATH="/opt/singularity/bin/singularity"
export CONTAINER_PATH="__CONDA_BASE__/__APPS_SUBDIR__/__CONDA_INSTALL_BASENAME__/etc/base.sif"
export CONDA_BASE_ENV_PATH="__CONDA_BASE__/__APPS_SUBDIR__/__CONDA_INSTALL_BASENAME__"

declare -a bind_dirs=( "/etc" "/half-root" "/local" "/ram" "/run" "/system" "/usr" "/var/lib/sss" "/var/run/munge" "/sys/fs/cgroup" "/iointensive" )
