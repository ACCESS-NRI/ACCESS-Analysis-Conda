### Settings to control installation path e.g. for test installs
export CONDA_BASE="${CONDA_BASE:-/g/data/xp65/public}"
export ADMIN_DIR="${ADMIN_DIR:-/g/data/xp65/admin/med_conda/admin}"
export CONDA_TEMP_PATH="${PBS_JOBFS:-${CONDA_TEMP_PATH}}"
export SCRIPT_DIR="${SCRIPT_DIR:-$PWD}"

export SCRIPT_SUBDIR="apps/med_conda_scripts"
export MODULE_SUBDIR="modules"
export APPS_SUBDIR="apps"
export CONDA_INSTALL_BASENAME="med_conda"
export MODULE_NAME="conda"

### Derived locations - extra '.' for arcane rsync magic
export CONDA_SCRIPT_PATH="${CONDA_BASE}"/./"${SCRIPT_SUBDIR}"
export CONDA_MODULE_PATH="${CONDA_BASE}"/./"${MODULE_SUBDIR}"/"${MODULE_NAME}"
export JOB_LOG_DIR="${ADMIN_DIR}"/logs
export BUILD_STAGE_DIR="${ADMIN_DIR}"/staging

### Groups
export APPS_USERS_GROUP=xp65
export APPS_OWNERS_GROUP=xp65_w

### Version settings
export ENVIRONMENT=access-med
export VERSION_TO_MODIFY=0.2
export STABLE_VERSION=0.1
export UNSTABLE_VERSION=0.2
export FULLENV="${ENVIRONMENT}-${VERSION_TO_MODIFY}"

### Other settings
export TEST_OUT_FILE=test_results.xml
export PYTHONNOUSERSITE=true
export CONTAINER_PATH=$( realpath "${SCRIPT_DIR}"/../container/base.sif )
export SINGULARITY_BINARY_PATH="/opt/singularity/bin/singularity"

declare -a rpms_to_remove=( "openssh-clients" "openssh-server" "openssh" )
declare -a replace_from_apps=( "openmpi/4.1.4" )
declare -a outside_commands_to_include=( "pbs_tmrsh" "ssh" )